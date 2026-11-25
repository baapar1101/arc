from typing import Literal

ProductDimensionUnit = Literal["um", "mm", "cm", "dm", "m", "km", "in", "ft", "yd", "mi"]
ProductWeightUnit = Literal["ug", "mg", "g", "kg", "t", "oz", "lb"]

MEASUREMENT_PRECISION = 27
MEASUREMENT_SCALE = 15
MEASUREMENT_FIELDS = {
    "length_mm": "طول به میلی‌متر",
    "width_mm": "عرض به میلی‌متر",
    "height_mm": "ارتفاع به میلی‌متر",
    "weight_g": "وزن به گرم",
}
