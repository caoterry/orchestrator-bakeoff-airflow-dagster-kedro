-- Quick sanity checks
SELECT ds, COUNT(*) AS rows_in_output
FROM poc.output_agg
GROUP BY ds
ORDER BY ds;

SELECT ds, category, total_amount
FROM poc.output_agg
ORDER BY ds, category;
