#include <stdio.h>
#include <stdint.h>
#include <math.h>


// 定義 bf16_t 結構
typedef union {
    uint16_t bits;  // 16-bit representation
} bf16_t;


static inline float bf16_to_fp32(bf16_t h)
{
    union {
        float f;
        uint32_t i;
    } u = {.i = (uint32_t)h.bits << 16};
    return u.f;
}

static inline bf16_t fp32_to_bf16(float s) {
    bf16_t h;
    union {
        float f;
        uint32_t i;
    } u = {.f = s};
    
    if ((u.i & 0x7fffffff) > 0x7f800000) 
    { // NaN
        h.bits = (u.i >> 16) | 0x0040; // force to quiet
        return h;                                                                                                                                             
    }
    
    h.bits = (u.i + (0x7fff + ((u.i >> 0x10) & 1))) >> 0x10;
    return h;
}

int getbit(int num, int position) {
    // Shift the desired bit to the least significant bit position and mask it
    return (num >> position) & 1;
}

static int32_t idiv24(int32_t a, int32_t b){
    uint32_t r = 0;
    for (int i = 0; i < 32; i++){
        r <<= 1;
        if (a - b < 0){
            a <<= 1;
            continue;
        }

        r |= 1;
        a -= b;
        a <<= 1;
    }

    return r;
}

float fdiv32(float a, float b)
{
    int32_t ia = *(int32_t *)&a, ib = *(int32_t *)&b;
    if (a == 0) return a;
    if (b == 0) return *(float*)&(int){0x7f800000};
    /* mantissa */
    int32_t ma = (ia & 0x7FFFFF) | 0x800000;
    int32_t mb = (ib & 0x7FFFFF) | 0x800000;

    /* sign and exponent */
    int32_t sea = ia & 0xFF800000;
    int32_t seb = ib & 0xFF800000;

    /* result of mantissa */
    int32_t m = idiv24(ma, mb);
    int32_t mshift = !getbit(m, 31);
    m <<= mshift;

    int32_t r = ((sea - seb + 0x3f800000) - (0x800000 & -mshift)) | (m & 0x7fffff00) >> 8;
    int32_t ovfl = (ia ^ ib ^ r) >> 31;
    r = r ^ ((r ^ 0x7f800000) & ovfl);
    
    return *(float *) &r;
    // return a / b;
}


float fp32_to_bf16_to_fp32(float s)
{

    bf16_t bf = fp32_to_bf16(s);
    return bf16_to_fp32(bf);
}


int main() {

    float dd[] = {1.0001f, 1.0f, 1000000.0f, 2.34180515202877589478e-38f, 3.3895313892515354759e+38f}; // 多組 dd 測試數據
    float dv[] = {1.0002f, 1000000.0f, 1.0f,1.0e-38f,1.0e+38f};              // 多組 dv 測試數據
    int num_tests = sizeof(dd) / sizeof(dd[0]);   // 測試組數
    float result_o = 0.0f;
    float result_q = 0.0f;
    float error = 0.0f;

    for (int i = 0; i < num_tests; i++) {
        // 使用 FP32 進行除法
        result_o = fdiv32(dd[i], dv[i]);
        printf("---- Test %d ----\n " ,i+1);
        printf("Original Result: %.6f\n",  result_o); // 輸出結果

        // 將 dd 和 dv 轉換為 BF16 再回到 FP32
        float dd_bf16 = fp32_to_bf16_to_fp32(dd[i]);
        float dv_bf16 = fp32_to_bf16_to_fp32(dv[i]);

        // 使用轉換後的 BF16 進行除法
        result_q = fdiv32(dd_bf16, dv_bf16);
        printf("Quantized Result: %.10f\n", result_q); // 輸出結果

        error = fabs(result_o - result_q) / fabs(result_o);
        printf("Relative Error: %.10f\n", error); // 輸出結果
    }

    return 0;
}
