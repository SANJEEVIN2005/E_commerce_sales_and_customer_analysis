SELECT table_name, COUNT(*) AS column_count
FROM   user_tab_columns
WHERE  table_name LIKE 'STG\_%' ESCAPE '\'
GROUP  BY table_name
ORDER  BY table_name;

SELECT value AS character_set
FROM   nls_database_parameters
WHERE  parameter = 'NLS_CHARACTERSET';