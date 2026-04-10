import psycopg2
import pandas as pd
import pickle
import os
from datetime import datetime

# ===============================
# 1. LOAD MODEL
# ===============================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "model.pkl")

with open(MODEL_PATH, "rb") as f:
    model = pickle.load(f)

print("Model loaded")

# ===============================
# 2. CONNECT POSTGRESQL
# ===============================
conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="pet_clinic_manager",
    user="postgres",
    password="sqlktb@12345"
)
cursor = conn.cursor()

print("Connected to DB")

# ===============================
# 3. LOAD FEATURES
# ===============================
query = """
SELECT 
    product_id,
    product_name,
    month_num,
    qty_sold,
    qty_purchased,
    stock,
    minimum_inventory
FROM v_ai_stock_features
ORDER BY product_id, month_num;
"""

df = pd.read_sql(query, conn)
print("Loaded:", len(df), "rows")

# --- FIX: convert month_num to int to avoid formatting errors ---
df["month_num"] = pd.to_numeric(df["month_num"], errors="coerce")
df["month_num"] = df["month_num"].fillna(1).astype(int)


# ===============================
# 4. EXTRA FEATURES
# ===============================
df["avg_3m_qty"] = (
    df.groupby("product_id")["qty_sold"]
      .rolling(3)
      .mean()
      .reset_index(0, drop=True)
      .fillna(0)
)

df["days_left"] = df.apply(
    lambda r: 999 if r["avg_3m_qty"] == 0 else r["stock"] / (r["avg_3m_qty"] / 30),
    axis=1
)

# ===============================
# 5. PREDICT
# ===============================
features = ["month_num", "qty_sold", "qty_purchased", "stock", "minimum_inventory"]
preds = model.predict(df[features])

df["predicted_quantity"] = pd.Series(preds).clip(0).astype(int)

# Confidence tạm tính
df["confidence"] = (1 / (1 + abs(df["qty_sold"] - df["stock"]))).round(2)

print("Predicted")

# ===============================
# 6. SAVE BASIC PREDICTIONS ONLY
# ===============================
insert_sql = """
INSERT INTO predictions (product_id, predicted_month, predicted_quantity, confidence, created_at)
VALUES (%s,%s,%s,%s,NOW())
ON CONFLICT (product_id, predicted_month)
DO UPDATE SET 
    predicted_quantity = EXCLUDED.predicted_quantity,
    confidence = EXCLUDED.confidence,
    created_at = NOW();
"""

count = 0
current_year = datetime.now().year

for idx, row in df.iterrows():
    # --- FIX: đảm bảo month_num là số nguyên khi format ---
    month = int(row["month_num"])
    predicted_month = f"{current_year}-{month:02d}"

    cursor.execute(insert_sql, (
        row["product_id"],
        predicted_month,
        int(row["predicted_quantity"]),
        float(row["confidence"])
    ))
    count += 1

conn.commit()
cursor.close()
conn.close()

print("Saved:", count)
print("Done")
