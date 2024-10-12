    .data
a:  .word 0x467432cd      # 被除數 (浮點數形式，單精度 FP32)
b:  .word 0x40212345      # 除數 (浮點數形式，單精度 FP32)
prompt: .string "answer = "  # 輸出提示字串
    .text
    .globl _start

_start:
    # 加載浮點數 a 和 b (作為無符號整數)
    la t0, a         # 加載 a 的地址
    lw t1, 0(t0)     # 將 a 的 32 位資料加載到 t1
    la t0, b         # 加載 b 的地址
    lw t2, 0(t0)     # 將 b 的 32 位資料加載到 t2
    
    mv a0, t1        # 將被除數 a 放入 a0 作為參數
    mv a1, t2        # 將除數 b 放入 a1 作為參數
    
    call fdiv32      # 呼叫 fdiv32 進行浮點數除法
    mv t1, a0        # 將除法結果存入 t1
    
    # 輸出字串 "answer = "
    la a0, prompt    # 加載字串地址
    li a7, 4         # 系統呼叫代碼 4 (打印字串)
    ecall            # 進行系統呼叫
    
    # 輸出除法結果
    mv a0, t1        # 將結果移到 a0
    li a7, 2         # 系統呼叫代碼 2 (打印整數)
    ecall            # 進行系統呼叫

    # 結束程式
    li a7, 10        # 系統呼叫代碼 10 (退出)
    ecall            # 進行系統呼叫
    
fdiv32:
    # 函數進入 - 保存返回地址
    addi sp, sp, -4
    sw ra, 0(sp)

    # 檢查除數 a1 是否為零，若為零則返回無窮大
    beqz a0, f3      # 若 a0 (被除數) 為 0，跳轉到 f3
    bnez a1, f1      # 若 a1 (除數) 不為 0，跳轉到 f1
    li a0, 0x7f800000  # a0 設定為正無窮大
    j f3             # 跳轉到函數結束
    
f1:
    # 提取浮點數的尾數部分
    li t2, 0x7FFFFF  # 尾數掩碼
    and t0, t2, a0   # 提取被除數 a 的尾數
    and t1, t2, a1   # 提取除數 b 的尾數
    addi t2, t2, 1   # 尾數位數加 1 (隱藏的 bit)
    or t0, t0, t2    # t0 = 被除數 a 的完整尾數
    or t1, t1, t2    # t1 = 除數 b 的完整尾數

idiv24:
    # 初始化除法過程
    li t3, 0        # 商 (t3) 初始化為 0
    li t4, 32       # 循環 32 次

f2:
    # 進行長除法，計算商
    sub t0, t0, t1  # 被除數減去除數
    sltz t2, t0     # 若 t0 < 0，則 t2 = 1，否則 t2 = 0
    seqz t2, t2     # t2 = !(t0 < 0)，將結果轉為 0 或 1
    slli t3, t3, 1  # 左移商
    or t3, t3, t2   # 將 t2 加入商中
    seqz t2, t2     # 取反 t2
    neg t2, t2      # 取負 t2 (轉換為 -1 或 0)
    and t5, t2, t1  # 若 t0 < 0，將 t1 加回去
    add t0, t0, t5  # 調整被除數
    slli t0, t0, 1  # 左移被除數以進行下一位

    addi t4, t4, -1 # 減少循環計數
    bnez t4, f2     # 若 t4 不為 0，繼續循環

    # 處理指數部分
    li t2, 0xFF800000  # 指數掩碼
    and t0, a0, t2     # 取出被除數的指數
    and t1, a1, t2     # 取出除數的指數
    mv a0, t3          # 將商存入 a0
    li a1, 31          # 設定 a1 為 31
    jal getbit         # 呼叫 getbit 函數計算尾數偏移
    seqz a0, a0        # 若 a0 為 0，則取反為 1，表示需要左移
    sll t3, t3, a0     # 將尾數左移以正規化

    # 計算最終的指數值
    li t2, 0x3f800000  # 基準指數 127
    sub t4, t0, t1     # 計算指數差
    add t4, t4, t2     # 加上基準指數
    neg a0, a0         # 若有左移，則減去一位
    li t2, 0x800000    # 尾數隱藏 bit
    and a0, a0, t2     # 隱藏 bit
    srli t3, t3, 8     # 右移尾數 8 位
    addi t2, t2, -1    # 調整掩碼
    and t3, t3, t2     # 掩碼尾數
    sub a0, t4, a0     # 計算最終結果
    or a0, a0, t3      # 合併指數和尾數

    # 溢位檢查
    xor t3, t1, t0     # 比較指數的符號
    xor t3, t3, a0     # 確定溢位
    srli t3, t3, 31    # 判斷是否發生溢位

    li t2, 0x7f800000  # 正無窮大的值
    xor t4, t2, a0     # 檢查結果是否無窮大
    and t4, t4, t3     # 若有溢位，結果為無窮大
    xor a0, a0, t4     # 更新最終結果

f3:
    # 函數退出 - 恢復返回地址
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

getbit:
    # 計算指定位置的位元值
    srl a0, a0, a1    # 右移 a0，移到指定位元
    andi a0, a0, 0x1  # 取出該位的值
    ret
