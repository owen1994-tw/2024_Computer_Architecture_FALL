.data
a:  .word 0x412c8390      # Dividend (floating-point format)
b:  .word 0x40000000      # Divisor (floating-point format)
prompt: .string "answer = "
.text
.globl _start

setup: 
    li ra,-1
    li sp, 0x7fffffff

_start:
    # Load floating-point numbers a and b (as unsigned integers)
    la t0, a         # Load address of a
    lw t1, 0(t0)     # Load 32-bit data of a into t1
    la t0, b         # Load address of b
    lw t2, 0(t0)     # Load 32-bit data of b into t2
    
    # Save return address ra and divisor onto the stack
    addi sp, sp, -8
    sw ra, 4(sp)
    sw t2, 0(sp)
    
    # Pass the dividend t1 to a0, prepare for FP32 to BF16 conversion
    mv a0, t1
    call fp32_to_bf16_fp32        # Convert dividend from FP32 to BF16
    mv t1, a0                # Save the converted dividend into t1

    # Restore return address and divisor
    lw ra, 4(sp)
    lw t2, 0(sp)
    sw t1, 0(sp)             # Save the converted dividend to the stack
    
    # Pass the divisor t2 to a0 for FP32 to BF16 conversion
    mv a0, t2
    call fp32_to_bf16_fp32        # Convert divisor from FP32 to BF16
    lw ra, 4(sp)
    lw t1, 0(sp)
    addi sp, sp, 8           # Restore stack pointer

    mv t2, a0                # Save the converted divisor into t2

    # Set parameters a0 and a1 for floating-point division
    mv a0, t1                # Dividend
    mv a1, t2                # Divisor
    
call_fdiv32:    
    call fdiv32              # Perform floating-point division
    mv t1,a0                 # Save the result into t1
    
    # Print the string "answer = "
    la a0, prompt            # Load the address of the string
    li a7, 4                 # Syscall code 4, print string
    ecall                    # Perform syscall
    
    # Print the floating-point division result (as an integer)
    mv a0, t1                # Store the result in a0
    li a7, 2                 # Syscall code 2, print integer
    ecall                    # Perform syscall

    # Exit program
    li a7, 10
    ecall



# Convert FP32 to BF16 and back to FP32
fp32_to_bf16_fp32:
    li t0, 0x7fffffff        # Load 0x7fffffff for masking
    li t1, 0x7f800000        # Load 0x7f800000 for NaN checking
    li t2, 64                # Load 64 for quiet NaN
    li t5, 0x7fff            # Load 0x7fff

    mv t3, a0                # Store FP32 floating-point number in t3

    # Check for NaN
    and t6, t0, t3           # Perform bitwise AND with 0x7fffffff
    bgtu t6, t1, handle_nan  # If result > 0x7f800000, branch to NaN handling

    # Normal processing
    srli t6, t3, 16          # Shift FP32 right by 16 bits
    andi t4, t6, 1           # Perform bitwise AND with 1 on (u >> 16)
    add t4, t4, t5           # Add 0x7fff to the result
    add t3, t3, t4           # Add result to u
    srli t3, t3, 16          # Shift right by 16 bits to get BF16
    j bf16_to_fp32
   

# NaN handling
handle_nan:
    srli t3, t3, 16          # Shift FP32 right by 16 bits
    or t3, t3, t2            # Perform bitwise OR with 64
    j bf16_to_fp32
    
bf16_to_fp32:
    slli a0, t3, 16          # Shift BF16 left by 16 bits to align with FP32
    ret

# 32-bit floating-point division
fdiv32:
    addi sp, sp, -4
    sw ra, 0(sp)

    beqz a0, f3              # If divisor is 0, return 0x7f800000
    bnez a1, f1              # Check if dividend is 0

    li a0, 0x7f800000        # Return positive infinity
    j f3

f1:
    li t2, 0x7FFFFF          # Mask for extracting mantissa
    and t0, t2, a0           # Extract dividend mantissa
    and t1, t2, a1           # Extract divisor mantissa
    addi t2, t2, 1           # Add 1 to handle rounding

    or t0, t0, t2            # Calculate dividend mantissa
    or t1, t1, t2            # Calculate divisor mantissa

idiv24:
    li t3, 0                 # Initialize quotient and remainder
    li t4, 32                # Set loop count for 32 bits

f2:
    sub t0, t0, t1           # Subtract divisor from dividend
    sltz t2, t0              # Check if result is negative
    seqz t2, t2              # t2 becomes 0 or 1
    slli t3, t3, 1           # Shift quotient left by 1 bit
    or t3, t3, t2            # Update quotient
    seqz t2, t2              # Invert t2
    neg t2, t2               # Take the negative value
    and t5, t2, t1           # If result is negative, set t5 to divisor
    add t0, t0, t5           # Restore dividend
    slli t0, t0, 1           # Shift dividend left by 1 bit

    addi t4, t4, -1          # Decrease loop count
    bnez t4, f2              # Continue looping

    li t2, 0xFF800000        # Extract exponent
    and t0, a0, t2           # Extract dividend exponent
    and t1, a1, t2           # Extract divisor exponent
    mv a0, t3                # Save quotient result

    # Handle result shifts
    li a1, 31
    jal getbit               # Check most significant bit

    seqz a0, a0              # Calculate shift amount
    sll t3, t3, a0           # Shift quotient left

    # Calculate new exponent
    li t2, 0x3f800000
    sub t4, t0, t1
    add t4, t4, t2           # Adjust exponent
    neg a0, a0               # Negate shift amount
    li t2, 0x800000
    and a0, a0, t2           # Handle shift effect
    srli t3, t3, 8           # Shift mantissa right by 8 bits
    addi t2, t2, -1
    and t3, t3, t2           # Align mantissa
    sub a0, t4, a0
    or a0, a0, t3            # Combine result
    
    # Check for overflow
    xor t3, t1, t0
    xor t3, t3, a0
    srli t3, t3, 31

    li t2, 0x7f800000
    xor t4, t2, a0
    and t4, t4, t3
    xor a0, a0, t4
f3:
    # Epilogue
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

getbit:
    # Prologue
    srl a0, a0, a1
    andi a0, a0, 0x1
    ret
