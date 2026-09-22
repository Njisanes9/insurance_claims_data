-- SQLite

-- A1. Displaying a count of active policies and the total monthly premium for each product type.

SELECT product_type, 
    COUNT(policy_id) AS active_policies, 
    SUM(premium_monthly) AS total_monthly_premium
FROM policies
WHERE policy_status = 'Active'
GROUP BY product_type
ORDER BY total_monthly_premium DESC;

-- A2. Displaying claim frequency and average claim amount for approved claims.

SELECT p.product_type, 
    CAST(COUNT(c.claim_id) AS REAL) / COUNT(DISTINCT p.policy_id) AS claim_frequency,
    AVG(c.claim_amount) AS average_claim_amount
FROM claims c
LEFT JOIN policies p
    ON c.policy_id = p.policy_id
WHERE c.claim_status = 'Approved'
GROUP BY p.product_type;

-- A3. Loss ratio by province. The results show that the the Mpumalanga province is the most profitable.

SELECT 
    cu.province,
    COALESCE(claims_by_prov.total_paid, 0) * 1.0 / SUM(p.premium_monthly * 12) AS loss_ratio
FROM customers cu
INNER JOIN policies p ON cu.customer_id = p.customer_id
LEFT JOIN (
    -- Subquery to get clean, independent total claims per province
    SELECT c_sub.province, SUM(cl.paid_amount) AS total_paid
    FROM customers c_sub
    INNER JOIN policies p_sub ON c_sub.customer_id = p_sub.customer_id
    INNER JOIN claims cl ON p_sub.policy_id = cl.policy_id
    WHERE cl.claim_status = 'Approved'
    GROUP BY c_sub.province
) claims_by_prov ON cu.province = claims_by_prov.province
GROUP BY cu.province
ORDER BY loss_ratio DESC;

-- A4 . Top 10 customers by total paid claims.

SELECT 
    cu.first_name || ' ' || cu.last_name AS customer_name, 
    cu.province, 
    SUM(c.paid_amount) AS total_paid  
FROM customers cu
INNER JOIN policies p ON cu.customer_id = p.customer_id
INNER JOIN claims c ON p.policy_id = c.policy_id
WHERE c.claim_status = 'Approved'
GROUP BY cu.customer_id, cu.first_name, cu.last_name, cu.province
ORDER BY total_paid DESC
LIMIT 10;

-- A5. Policies with more than one claim within it's firsy 90 days.

SELECT
    p.policy_id,
    p.customer_id,
    p.product_type,
    COUNT(c.claim_id) AS early_claims
FROM policies p
INNER JOIN claims c ON p.policy_id = c.policy_id
WHERE c.claim_date >= p.inception_date
  AND c.claim_date <= date(p.inception_date, '+90 days') -- Standard inclusion usually includes the 90th day
GROUP BY
    p.policy_id,
    p.customer_id,
    p.product_type
HAVING COUNT(c.claim_id) > 1;

-- A6. On time payment rate by product type.

SELECT 
    p.product_type,
    AVG(policy_payment_rates.on_time_rate) AS avg_on_time_payment_rate
FROM policies p
INNER JOIN (

    SELECT 
        policy_id,
        SUM(CASE WHEN payment_status = 'Paid' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS on_time_rate
    FROM payments
    GROUP BY policy_id
) AS policy_payment_rates ON p.policy_id = policy_payment_rates.policy_id
GROUP BY p.product_type
ORDER BY avg_on_time_payment_rate ASC;

-- A7: Rank customers within each province by total annualised premium

WITH customer_premiums AS (
    -- Step 1: Calculate total annualized premium per unique customer
    SELECT 
        cu.customer_id,
        cu.first_name || ' ' || cu.last_name AS customer_name,
        cu.province,
        SUM(p.premium_monthly * 12) AS total_annualised_premium
    FROM customers cu
    INNER JOIN policies p ON cu.customer_id = p.customer_id
    GROUP BY cu.customer_id, cu.first_name, cu.last_name, cu.province
)
-- Step 2: Apply the window function to rank them within their province
SELECT 
    province,
    customer_name,
    total_annualised_premium,
    RANK() OVER (
        PARTITION BY province 
        ORDER BY total_annualised_premium DESC
    ) AS premium_rank
FROM customer_premiums
ORDER BY province ASC, premium_rank ASC;

-- Bonus A8: Unified Customer-Level Analytical View


WITH customer_policy_mix AS (
    -- Aggregate policy metrics and group product types into a readable string
    SELECT 
        customer_id,
        GROUP_CONCAT(DISTINCT product_type) AS product_mix,
        SUM(premium_monthly * 12) AS total_annualised_premium
    FROM policies
    GROUP BY customer_id
),

customer_claims AS (
    -- Aggregate total approved paid claims per customer
    SELECT 
        p.customer_id,
        SUM(c.paid_amount) AS total_claims_paid
    FROM policies p
    INNER JOIN claims c ON p.policy_id = c.policy_id
    WHERE c.claim_status = 'Approved'
    GROUP BY p.customer_id
),

customer_payments AS (
    -- Calculate individual customer-level on-time payment rate
    SELECT 
        p.customer_id,
        SUM(CASE WHEN pay.payment_status = 'Paid' THEN 1 ELSE 0 END) 
        * 1.0 / COUNT(pay.payment_id) AS on_time_payment_rate
    FROM policies p
    INNER JOIN payments pay ON p.policy_id = pay.policy_id
    GROUP BY p.customer_id
)

-- Main query stitching the independent profiles together
SELECT 
    cu.customer_id,
    cu.first_name || ' ' || cu.last_name AS customer_name,
    cu.province,
    COALESCE(pm.product_mix, 'No Active Products') AS product_mix,
    COALESCE(pm.total_annualised_premium, 0.0) AS total_annualised_premium,
    COALESCE(cc.total_claims_paid, 0.0) AS total_claims_paid,
    ROUND(COALESCE(cp.on_time_payment_rate, 0.0), 4) AS on_time_payment_rate
FROM customers cu
LEFT JOIN customer_policy_mix pm ON cu.customer_id = pm.customer_id
LEFT JOIN customer_claims cc ON cu.customer_id = cc.customer_id
LEFT JOIN customer_payments cp ON cu.customer_id = cp.customer_id;
