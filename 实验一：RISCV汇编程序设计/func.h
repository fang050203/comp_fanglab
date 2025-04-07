typedef unsigned int uint32;

uint32 fadd(uint32 num1, uint32 num2)
{
    uint32 sign1 = (num1 & 0x80000000) >> 31;   // 符号位S1
    uint32 sign2 = (num2 & 0x80000000) >> 31;   // 符号位S2
    uint32 exp1  = (num1 & 0x7f800000) >> 23;   // 阶码E1
    uint32 exp2  = (num2 & 0x7f800000) >> 23;   // 阶码E2
    uint32 mant1 = (num1 & 0x007fffff);         // 尾数M1
    uint32 mant2 = (num2 & 0x007fffff);         // 尾数M2

    mant1 |= 0x00800000;    // {1'b1, M1}
    mant2 |= 0x00800000;    // {1'b1, M2}

    uint32 exp_delta = exp1 - exp2;     // 求阶差
    mant2 >>= exp_delta;                // 对阶

    uint32 sign = sign1;                // 结果的符号
    uint32 exp  = exp1;                 // 结果的阶码
    uint32 mant = mant1 + mant2;        // 结果的尾数

    if ((mant & 0xff000000) != 0)       // 尾数位宽大于24则右规
    {
        mant >>= 1;
        exp += 1;
    }

    mant &= 0x007fffff;                 // 去除尾数的“隐藏1”

    uint32 result = (sign << 31) | (exp << 23) | mant;
    return result;
}
