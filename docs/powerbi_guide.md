# Power BI Connection Guide — Oracle 21c XE

Connect Power BI Desktop to the star schema tables built in this project.

---

## Step 1 — Install the Oracle ODBC Driver

Power BI Desktop connects to Oracle via the **Oracle Data Provider for .NET (ODP.NET)**
or the **Oracle ODBC Driver**. The easiest path on Windows:

1. Download **Oracle Instant Client** (Basic + ODAC) for Windows 64-bit from:  
   https://www.oracle.com/database/technologies/instant-client/winx64-64-downloads.html
2. Extract to e.g. `C:\oracle\instantclient_21_12`
3. Add that folder to your **System PATH**
4. Restart Power BI Desktop

> If Oracle 21c XE is already installed at `D:\Downloads\Oracle21c\dbhomeXE`, Power BI
> can use that client directly — just make sure `D:\Downloads\Oracle21c\dbhomeXE\bin`
> is on your system PATH.

---

## Step 2 — Connect from Power BI Desktop

1. Open Power BI Desktop → **Home → Get Data → More…**
2. Search **Oracle** → select **Oracle database** → **Connect**
3. Fill in the connection dialog:

| Field | Value |
|---|---|
| Server | `localhost:1521/XEPDB1` |
| Data Connectivity mode | **Import** (recommended for a portfolio) |

4. Click **OK** → enter credentials:
   - User name: `projectuser`
   - Password: *(your Oracle password)*
5. Click **Connect**

---

## Step 3 — Select Tables

In the Navigator window, expand **PROJECTUSER** and select:

```
✅ dim_date
✅ dim_customer
✅ dim_seller
✅ dim_product
✅ fact_orders
✅ fact_order_items
```

Click **Load** (or **Transform Data** to preview first).

---

## Step 4 — Set Up Relationships (Data Model)

Go to **Model view** and create these relationships manually if Power BI doesn't auto-detect them:

| From (Fact) | Key | To (Dim) | Key | Cardinality |
|---|---|---|---|---|
| fact_orders | PURCHASE_DATE_KEY | dim_date | DATE_KEY | Many → One |
| fact_orders | CUSTOMER_KEY | dim_customer | CUSTOMER_KEY | Many → One |
| fact_order_items | ORDER_ID | fact_orders | ORDER_ID | Many → One |
| fact_order_items | PRODUCT_KEY | dim_product | PRODUCT_KEY | Many → One |
| fact_order_items | SELLER_KEY | dim_seller | SELLER_KEY | Many → One |
| fact_order_items | SHIP_DATE_KEY | dim_date | DATE_KEY | Many → One |

> For the two dim_date relationships (purchase + ship date), set the **ship_date** one as
> **inactive** and activate it using `USERELATIONSHIP()` in DAX when needed.

---

## Step 5 — Key DAX Measures

Create these in a **Measures** table (Home → New measure):

```dax
-- Total Revenue (excludes cancelled/unavailable)
Total Revenue =
CALCULATE(
    SUM(fact_orders[TOTAL_REVENUE]),
    NOT fact_orders[ORDER_STATUS] IN {"canceled", "unavailable"}
)

-- Total Orders
Total Orders =
CALCULATE(
    COUNTROWS(fact_orders),
    NOT fact_orders[ORDER_STATUS] IN {"canceled", "unavailable"}
)

-- Avg Order Value
Avg Order Value = DIVIDE([Total Revenue], [Total Orders])

-- Avg Delivery Days
Avg Delivery Days =
CALCULATE(
    AVERAGE(fact_orders[DAYS_TO_DELIVERY]),
    fact_orders[ORDER_STATUS] = "delivered",
    NOT ISBLANK(fact_orders[DAYS_TO_DELIVERY])
)

-- Late Delivery Rate %
Late Rate % =
CALCULATE(
    DIVIDE(
        COUNTROWS(FILTER(fact_orders, fact_orders[IS_LATE] = 1)),
        COUNTROWS(FILTER(fact_orders, NOT ISBLANK(fact_orders[IS_LATE])))
    ) * 100,
    fact_orders[ORDER_STATUS] = "delivered"
)

-- Avg Review Score
Avg Review Score =
CALCULATE(
    AVERAGE(fact_orders[REVIEW_SCORE]),
    NOT ISBLANK(fact_orders[REVIEW_SCORE])
)

-- Revenue by Category (uses fact_order_items grain)
Revenue by Category =
SUMX(
    fact_order_items,
    fact_order_items[PRICE]
)
```

---

## Step 6 — Suggested Visuals

| Page | Visual | Fields |
|---|---|---|
| **Overview** | Card × 4 | Total Revenue, Total Orders, Avg Delivery Days, Avg Review Score |
| **Overview** | Line chart | Axis: dim_date[MONTH_NAME] + YEAR · Values: Total Revenue |
| **Overview** | Donut | Legend: fact_orders[ORDER_STATUS] · Values: Total Orders |
| **Categories** | Bar chart | Axis: dim_product[PRODUCT_CATEGORY_NAME_ENGLISH] · Values: Revenue by Category |
| **Categories** | Scatter | X: Avg Delivery Days · Y: Avg Review Score · Size: Total Orders |
| **Customers** | Map | Location: dim_customer[CUSTOMER_STATE] · Size: Total Orders |
| **Customers** | Bar | Axis: RFM Segment (custom column) · Values: customer count |
| **Sellers** | Table | dim_seller columns + measures |
| **Payments** | Donut | Legend: payment_type · Values: total_paid (from clean_order_payments) |
| **Delivery** | Histogram | Bucket column on DAYS_TO_DELIVERY |

---

## Optional — Direct Query Mode

If your Oracle VM has enough RAM, you can use **DirectQuery** instead of Import.
This means Power BI sends SQL to Oracle on every interaction — always fresh data,
but slower for large datasets. For this 99K-order dataset, **Import is faster**.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `Oracle: ORA-12154: TNS could not resolve` | Check server string is `localhost:1521/XEPDB1` (not just `localhost`) |
| `Could not load type 'Oracle.DataAccess'` | Install 64-bit ODP.NET; Power BI Desktop is 64-bit |
| `ORA-01017: invalid username/password` | Check user is `projectuser` (lowercase) and password is correct |
| Tables not visible in Navigator | Expand the `PROJECTUSER` schema node specifically |
