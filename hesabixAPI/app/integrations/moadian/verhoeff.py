"""
پیاده‌سازی الگوریتم Verhoeff برای محاسبه checksum
مطابق VerhoeffService در کتابخانه PHP
"""

# جداول Verhoeff
MULTIPLICATION_TABLE = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
]

PERMUTATION_TABLE = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
    [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
]

INVERSE_TABLE = [0, 4, 3, 2, 1, 5, 6, 7, 8, 9]


def verhoeff_checksum(number: str) -> int:
    """
    محاسبه checksum با الگوریتم Verhoeff
    مطابق VerhoeffService::checkSum در PHP
    
    Args:
        number: رشته عددی
    
    Returns:
        checksum (0-9)
    """
    c = 0
    number_str = str(number)
    length = len(number_str)
    
    for i in range(length):
        pos = length - i - 1
        digit = int(number_str[pos])
        perm_index = (i + 1) % 8
        c = MULTIPLICATION_TABLE[c][PERMUTATION_TABLE[perm_index][digit]]
    
    return INVERSE_TABLE[c]


def verhoeff_validate(number: str) -> bool:
    """
    اعتبارسنجی عدد با الگوریتم Verhoeff
    مطابق VerhoeffService::validate در PHP
    
    Args:
        number: رشته عددی
    
    Returns:
        True اگر معتبر باشد
    """
    c = 0
    number_str = str(number)
    length = len(number_str)
    
    for i in range(length):
        pos = length - i - 1
        digit = int(number_str[pos])
        perm_index = i % 8
        c = MULTIPLICATION_TABLE[c][PERMUTATION_TABLE[perm_index][digit]]
    
    return c == 0





