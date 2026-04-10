import pandas as pd
import numpy as np

np.random.seed(42)

YEARS = 3
MONTHS = YEARS * 12

products = [
    "Băng gạc y tế vô trùng",
    "Vitamin bổ sung cho thú cưng",
    "Xà phòng tắm cho chó mèo",
    "Máy đo huyết áp thú y",
    "Vòng cổ chống ve rận",
    "Khăn lau vệ sinh",
    "Thuốc nhỏ mắt cho thú cưng",
    "Bột dinh dưỡng cho chim",
    "Vitamin C cho thỏ",
    "Kim tiêm dùng một lần",
    "Thuốc tẩy giun cho chó",
    "Găng tay y tế",
    "Máy cắt lông thú cưng",
    "Bình xịt khử mùi",
    "Sữa bột cho mèo con",
    "Thuốc kháng sinh Amoxicillin cho chó",
    "Vắc-xin phòng dại cho mèo",
    "Thức ăn khô cho chó trưởng thành",
    "Lồng vận chuyển chó mèo",
    "Thức ăn ướt cho mèo"
]

data_rows = []

def season_sell(month, low, high):
    """Random bán theo mùa"""
    return np.random.randint(low, high)

for pid, name in enumerate(products, start=1):
    stock = np.random.randint(40, 120)
    minimum_inventory = np.random.randint(10, 30)

    for month in range(1, MONTHS + 1):
        month_num = ((month - 1) % 12) + 1

        # A) Thuốc – vitamin – kháng sinh – vaccine
        if name in [
            "Vitamin bổ sung cho thú cưng",
            "Thuốc nhỏ mắt cho thú cưng",
            "Vitamin C cho thỏ",
            "Thuốc tẩy giun cho chó",
            "Thuốc kháng sinh Amoxicillin cho chó",
            "Vắc-xin phòng dại cho mèo"
        ]:
            if month_num in [1,2,3,9,10,11,12]:
                qty_sold = season_sell(month_num, 15, 40)
            else:
                qty_sold = season_sell(month_num, 5, 20)

        # B) Thức ăn – sữa – dinh dưỡng
        elif name in [
            "Bột dinh dưỡng cho chim",
            "Sữa bột cho mèo con",
            "Thức ăn khô cho chó trưởng thành",
            "Thức ăn ướt cho mèo"
        ]:
            if month_num in [11,12]:  # mua cuối năm
                qty_sold = season_sell(month_num, 20, 35)
            else:
                qty_sold = season_sell(month_num, 12, 25)

        # C) Chăm sóc – vệ sinh
        elif name in [
            "Xà phòng tắm cho chó mèo",
            "Bình xịt khử mùi",
            "Khăn lau vệ sinh"
        ]:
            if month_num in [5,6,7,8]:  # nóng, thú cưng cần tắm nhiều
                qty_sold = season_sell(month_num, 18, 35)
            else:
                qty_sold = season_sell(month_num, 8, 20)

        # D) Chống ve rận
        elif name == "Vòng cổ chống ve rận":
            if month_num in [7,8,9,10,11]:  # mùa mưa
                qty_sold = season_sell(month_num, 20, 45)
            else:
                qty_sold = season_sell(month_num, 5, 18)

        # E) Thiết bị – dụng cụ y tế
        else:
            if month_num in [1,4,9]:  # nhập thiết bị vào các kỳ
                qty_sold = season_sell(month_num, 10, 25)
            else:
                qty_sold = season_sell(month_num, 3, 12)

        # Nhập kho (realistic)
        if stock < minimum_inventory * 1.3:
            qty_purchased = np.random.randint(20, 70)
        else:
            qty_purchased = np.random.randint(0, 25) if np.random.rand() < 0.2 else 0

        # Cập nhật tồn kho
        stock = max(0, stock - qty_sold + qty_purchased)

        data_rows.append({
            "product_id": pid,
            "product_name": name,
            "month_num": month_num,
            "qty_sold": qty_sold,
            "qty_purchased": qty_purchased,
            "stock": stock,
            "minimum_inventory": minimum_inventory
        })

# Xuất CSV
df = pd.DataFrame(data_rows)
df.to_csv("fake_data_20_products_realistic.csv", index=False)
print("Đã tạo file fake_data_20_products_realistic.csv (3 năm, 20 sản phẩm)")
