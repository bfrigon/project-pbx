DELETE FROM cdr WHERE dst="s";
DELETE FROM cdr WHERE type="feature" AND calldate < DATE(NOW()- INTERVAL 5 DAY);
DELETE FROM cdr WHERE type="local" AND calldate < DATE(NOW() - INTERVAL 30 DAY);
DELETE FROM cdr WHERE calldate < DATE(NOW() - INTERVAL 600 DAY);


