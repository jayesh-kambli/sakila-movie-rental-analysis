-- What are the purchasing patterns of new customers versus repeat customers?
WITH customer_payments AS (
    SELECT
        customer_id,
        payment_id,
        payment_date,
        amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY payment_date
        ) AS purchase_number
    FROM payment
),
classified_payments AS (
    SELECT
        *,
        CASE
            WHEN purchase_number = 1 THEN 'New Customer'
            ELSE 'Repeating Customer'
        END AS customer_type
    FROM customer_payments
)

SELECT
    customer_type,
    COUNT(*) AS total_purchases,
    COUNT(DISTINCT customer_id) AS unique_customers,
    ROUND(AVG(amount), 2) AS avg_purchase_amount,
    SUM(amount) AS total_revenue
FROM classified_payments
GROUP BY customer_type
ORDER BY customer_type;

-- Which films have the highest rental rates and are most in demand?
WITH rental_count AS (
    SELECT
        i.film_id,
        COUNT(*) AS times_rented
    FROM rental r
    JOIN inventory i ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)
SELECT
    f.film_id,
    f.title,
    f.rental_rate,
    COALESCE(rc.times_rented, 0) AS times_rented
FROM film f
LEFT JOIN rental_count rc
    ON f.film_id = rc.film_id
ORDER BY
    f.rental_rate DESC,
    times_rented DESC;

-- Are there correlations between staff performance and customer satisfaction?
WITH customer_stats AS (
    SELECT
        customer_id,
        COUNT(*) AS total_rentals,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
),

customer_segment AS (
    SELECT *,
        CASE
            WHEN total_rentals >= 20 THEN 'High Value'
            ELSE 'Low Value'
        END AS customer_type
    FROM customer_stats
)

SELECT
    s.staff_id,
    CONCAT(s.first_name, ' ', s.last_name) AS staff_name,
    COUNT(DISTINCT r.rental_id) AS rentals_handled,
    ROUND(SUM(p.amount),2) AS revenue_generated,

    COUNT(DISTINCT CASE
        WHEN cs.customer_type = 'High Value'
        THEN r.customer_id
    END) AS high_value_customers,

    COUNT(DISTINCT CASE
        WHEN cs.customer_type = 'Low Value'
        THEN r.customer_id
    END) AS low_value_customers

FROM staff s
JOIN rental r
    ON s.staff_id = r.staff_id
JOIN payment p
    ON r.rental_id = p.rental_id
JOIN customer_segment cs
    ON r.customer_id = cs.customer_id

GROUP BY
    s.staff_id,
    staff_name;

-- Are there seasonal trends in customer behavior across different locations?
SELECT
    c.country,
    DATE_TRUNC('month', r.rental_date) AS month,
    COUNT(r.rental_id) AS total_rentals,
    ROUND(SUM(p.amount), 2) AS total_revenue
FROM rental r
JOIN payment p
    ON r.rental_id = p.rental_id
JOIN customer cu
    ON r.customer_id = cu.customer_id
JOIN address a
    ON cu.address_id = a.address_id
JOIN city ci
    ON a.city_id = ci.city_id
JOIN country c
    ON ci.country_id = c.country_id
GROUP BY
    c.country,
    DATE_TRUNC('month', r.rental_date)
ORDER BY
    c.country,
    month;

-- Are certain language films more popular among specific customer segments?
WITH customer_spending AS (
    SELECT
        customer_id,
        SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
),

customer_segment AS (
    SELECT
        customer_id,
        total_spent,
        CASE
            WHEN total_spent >= (
                SELECT AVG(total_spent)
                FROM customer_spending
            )
            THEN 'High Value'
            ELSE 'Low Value'
        END AS customer_segment
    FROM customer_spending
)

SELECT
    cs.customer_segment,
    l.name AS language,
    COUNT(*) AS total_rentals
FROM customer_segment cs
JOIN rental r
    ON cs.customer_id = r.customer_id
JOIN inventory i
    ON r.inventory_id = i.inventory_id
JOIN film f
    ON i.film_id = f.film_id
JOIN language l
    ON f.language_id = l.language_id
GROUP BY
    cs.customer_segment,
    l.name
ORDER BY
    cs.customer_segment,
    total_rentals DESC;


-- How does customer loyalty impact sales revenue over time?
WITH customer_loyalty AS (
    SELECT
        customer_id,
        COUNT(*) AS total_rentals
    FROM rental
    GROUP BY customer_id
),

customer_segment AS (
    SELECT
        customer_id,
        CASE
            WHEN total_rentals >= (
                SELECT AVG(total_rentals)
                FROM customer_loyalty
            )
            THEN 'Loyal Customer'
            ELSE 'Occasional Customer'
        END AS loyalty_segment
    FROM customer_loyalty
)

SELECT
    DATE_TRUNC('month', p.payment_date) AS month,
    cs.loyalty_segment,
    COUNT(DISTINCT p.customer_id) AS active_customers,
    COUNT(p.payment_id) AS total_transactions,
    ROUND(SUM(p.amount),2) AS total_revenue,
    ROUND(AVG(p.amount),2) AS avg_transaction_value
FROM payment p
JOIN customer_segment cs
    ON p.customer_id = cs.customer_id
GROUP BY
    DATE_TRUNC('month', p.payment_date),
    cs.loyalty_segment
ORDER BY
    month,
    cs.loyalty_segment;

-- Are certain film categories more popular in specific locations?
SELECT
    co.country,
    c.name AS category,
    COUNT(r.rental_id) AS total_rentals,
    ROUND(SUM(p.amount), 2) AS total_revenue
FROM rental r
JOIN payment p
    ON r.rental_id = p.rental_id
JOIN inventory i
    ON r.inventory_id = i.inventory_id
JOIN film f
    ON i.film_id = f.film_id
JOIN film_category fc
    ON f.film_id = fc.film_id
JOIN category c
    ON fc.category_id = c.category_id
JOIN customer cu
    ON r.customer_id = cu.customer_id
JOIN address a
    ON cu.address_id = a.address_id
JOIN city ci
    ON a.city_id = ci.city_id
JOIN country co
    ON ci.country_id = co.country_id
GROUP BY
    co.country,
    c.name
ORDER BY
    co.country,
    total_rentals DESC;

-- How does the availability and knowledge of staff affect customer ratings?
SELECT
    s.staff_id,
    CONCAT(s.first_name, ' ', s.last_name) AS staff_name,
    s.store_id,
    f.rating AS film_rating,

    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,

    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(AVG(p.amount), 2) AS avg_revenue_per_rental,

    ROUND(
        AVG(
            EXTRACT(EPOCH FROM (r.return_date - r.rental_date)) / 86400
        ),
        2
    ) AS avg_rental_days,

    RANK() OVER (
        PARTITION BY f.rating
        ORDER BY COUNT(r.rental_id) DESC
    ) AS rank_by_rating

FROM rental r
JOIN staff s
    ON r.staff_id = s.staff_id
JOIN payment p
    ON r.rental_id = p.rental_id
JOIN inventory i
    ON r.inventory_id = i.inventory_id
JOIN film f
    ON i.film_id = f.film_id

GROUP BY
    s.staff_id,
    s.first_name,
    s.last_name,
    s.store_id,
    f.rating

ORDER BY
    s.staff_id,
    total_rentals DESC;

-- How does the proximity of stores to customers impact rental frequency?
SELECT
    s.store_id,
    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,
    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(COUNT(r.rental_id)::numeric /
          COUNT(DISTINCT r.customer_id), 2) AS avg_rentals_per_customer
FROM rental r
JOIN payment p
    ON r.rental_id = p.rental_id
JOIN customer c
    ON r.customer_id = c.customer_id
JOIN store s
    ON c.store_id = s.store_id
GROUP BY s.store_id
ORDER BY total_rentals DESC;

-- Do specific film categories attract different age groups of customers?
SELECT
    CASE f.rating
        WHEN 'G' THEN 'Children/Family (G)'
        WHEN 'PG' THEN 'Pre-teens (PG)'
        WHEN 'PG-13' THEN 'Teens (PG-13)'
        WHEN 'R' THEN 'Adults (R)'
        WHEN 'NC-17' THEN 'Mature Adults (NC-17)'
    END AS age_group,

    ca.name AS category,

    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,
    ROUND(SUM(p.amount), 2) AS total_revenue,

    RANK() OVER (
        PARTITION BY f.rating
        ORDER BY COUNT(r.rental_id) DESC
    ) AS category_rank_in_age_group

FROM rental r
JOIN inventory i
    ON r.inventory_id = i.inventory_id
JOIN film f
    ON i.film_id = f.film_id
JOIN film_category fc
    ON f.film_id = fc.film_id
JOIN category ca
    ON fc.category_id = ca.category_id
JOIN payment p
    ON r.rental_id = p.rental_id

GROUP BY
    f.rating,
    ca.name

ORDER BY
    f.rating,
    total_rentals DESC;


-- What are the demographics and preferences of the highest-spending customers?
WITH customer_spend AS (
    SELECT
        c.customer_id,
        c.store_id,
        c.active,
        co.country,
        ROUND(SUM(p.amount), 2) AS total_spend,
        COUNT(r.rental_id) AS total_rentals,
        RANK() OVER (ORDER BY SUM(p.amount) DESC) AS spend_rank
    FROM customer c
    JOIN address a
        ON c.address_id = a.address_id
    JOIN city ci
        ON a.city_id = ci.city_id
    JOIN country co
        ON ci.country_id = co.country_id
    JOIN rental r
        ON c.customer_id = r.customer_id
    JOIN payment p
        ON r.rental_id = p.rental_id
    GROUP BY
        c.customer_id,
        c.store_id,
        c.active,
        co.country
),

customer_preferences AS (
    SELECT
        r.customer_id,
        ca.name AS category,
        f.rating,
        COUNT(*) AS rentals,
        RANK() OVER (
            PARTITION BY r.customer_id
            ORDER BY COUNT(*) DESC
        ) AS preference_rank
    FROM rental r
    JOIN inventory i
        ON r.inventory_id = i.inventory_id
    JOIN film f
        ON i.film_id = f.film_id
    JOIN film_category fc
        ON f.film_id = fc.film_id
    JOIN category ca
        ON fc.category_id = ca.category_id
    GROUP BY
        r.customer_id,
        ca.name,
        f.rating
)

SELECT
    cs.spend_rank,
    cs.customer_id,
    cs.country,
    cs.store_id,
    cs.active,
    cs.total_spend,
    cs.total_rentals,
    cp.category AS favorite_category,
    cp.rating AS preferred_film_rating
FROM customer_spend cs
LEFT JOIN customer_preferences cp
    ON cs.customer_id = cp.customer_id
   AND cp.preference_rank = 1
WHERE cs.spend_rank <= 20
ORDER BY
    cs.spend_rank;

-- How does the availability of inventory impact customer satisfaction and repeat business?

WITH film_stock AS (
    SELECT
        i.film_id,
        COUNT(i.inventory_id) AS copies_available
    FROM inventory i
    GROUP BY i.film_id
),

film_demand AS (
    SELECT
        i.film_id,
        COUNT(r.rental_id) AS total_rentals
    FROM rental r
    JOIN inventory i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)

SELECT
    CASE
        WHEN (fd.total_rentals::numeric / fs.copies_available) <= 3.0
            THEN 'Low Demand (<=3.0/copy)'

        WHEN (fd.total_rentals::numeric / fs.copies_available) <= 3.6
            THEN 'Medium Demand (3.0-3.6)'

        ELSE 'High Demand (>3.6/copy)'
    END AS demand_tier,

    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,

    ROUND(SUM(p.amount),2) AS total_revenue,
    ROUND(AVG(p.amount),2) AS avg_revenue_per_rental

FROM rental r
JOIN inventory i
    ON r.inventory_id = i.inventory_id
JOIN film_stock fs
    ON i.film_id = fs.film_id
JOIN film_demand fd
    ON i.film_id = fd.film_id
JOIN payment p
    ON r.rental_id = p.rental_id

GROUP BY demand_tier
ORDER BY total_rentals DESC;

-- What are the busiest hours or days for each store location, and how does it impact staffing requirements?
SELECT
    c.store_id,

    TO_CHAR(r.rental_date, 'Day') AS day_of_week,
    EXTRACT(HOUR FROM r.rental_date) AS hour_of_day,

    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,
    ROUND(SUM(p.amount), 2) AS total_revenue,

    RANK() OVER (
        PARTITION BY c.store_id
        ORDER BY COUNT(r.rental_id) DESC
    ) AS busy_rank_in_store

FROM rental r
JOIN customer c
    ON r.customer_id = c.customer_id
JOIN payment p
    ON r.rental_id = p.rental_id

GROUP BY
    c.store_id,
    TO_CHAR(r.rental_date, 'Day'),
    EXTRACT(HOUR FROM r.rental_date)

ORDER BY
    c.store_id,
    busy_rank_in_store;

-- What are the cultural or demographic factors that influence customer preferences in different locations?
SELECT *
FROM (
    SELECT
        CASE
            WHEN co.country IN ('India','China','Japan','Philippines','Indonesia','Vietnam',
                                'Thailand','Pakistan','Turkey')
                THEN 'Asia'

            WHEN co.country IN ('Russian Federation','Germany','France',
                                'United Kingdom','Italy','Spain','Poland')
                THEN 'Europe'

            WHEN co.country IN ('United States','Canada','Mexico')
                THEN 'North America'

            WHEN co.country IN ('Brazil','Argentina','Colombia',
                                'Venezuela','Peru')
                THEN 'South America'

            WHEN co.country IN ('Nigeria','Egypt','South Africa',
                                'Algeria','Morocco','Sudan')
                THEN 'Africa'

            ELSE 'Other'
        END AS region,

        ca.name AS category,

        COUNT(r.rental_id) AS total_rentals,
        ROUND(SUM(p.amount),2) AS total_revenue,
        ROUND(AVG(p.amount),2) AS avg_spend

    FROM rental r

    JOIN customer c
        ON r.customer_id = c.customer_id

    JOIN address a
        ON c.address_id = a.address_id

    JOIN city ci
        ON a.city_id = ci.city_id

    JOIN country co
        ON ci.country_id = co.country_id

    JOIN inventory i
        ON r.inventory_id = i.inventory_id

    JOIN film f
        ON i.film_id = f.film_id

    JOIN film_category fc
        ON f.film_id = fc.film_id

    JOIN category ca
        ON fc.category_id = ca.category_id

    JOIN payment p
        ON r.rental_id = p.rental_id

    GROUP BY
        region,
        ca.name
) AS regional_summary
ORDER BY
    region,
    total_rentals DESC;

-- How does the availability of films in different languages impact customer satisfaction and rental frequency?
WITH film_stock AS (
    SELECT
        film_id,
        COUNT(inventory_id) AS copies_available
    FROM inventory
    GROUP BY film_id
)

SELECT
    l.name AS language,
    COUNT(r.rental_id) AS total_rentals,
    COUNT(DISTINCT r.customer_id) AS unique_customers,
    ROUND(AVG(fs.copies_available), 2) AS avg_copies_available,
    ROUND(SUM(p.amount), 2) AS total_revenue,
    ROUND(AVG(p.amount), 2) AS avg_rental_amount,
    ROUND(
        COUNT(r.rental_id)::numeric /
        COUNT(DISTINCT r.customer_id), 2
    ) AS avg_rentals_per_customer

FROM rental r

JOIN inventory i
    ON r.inventory_id = i.inventory_id

JOIN film f
    ON i.film_id = f.film_id

JOIN language l
    ON f.language_id = l.language_id

JOIN film_stock fs
    ON f.film_id = fs.film_id

JOIN payment p
    ON r.rental_id = p.rental_id

GROUP BY
    l.name

ORDER BY
    total_rentals DESC;

select * from rental
select * from public.inventory
select * from film
select * from customer
select * from address
select * from city
select * from country
select * from staff
select * from payment
select * from language