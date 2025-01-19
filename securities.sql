-- roles.sql
CREATE ROLE kitchen_manager;
GRANT SELECT ON order_analytics TO kitchen_manager;
CREATE ROLE financial_analyst;
GRANT SELECT ON financial_metrics TO financial_analyst;

-- audit.sql
CREATE TRIGGER audit_sensitive_data
AFTER UPDATE ON customer_data
FOR EACH ROW
INSERT INTO audit_log;