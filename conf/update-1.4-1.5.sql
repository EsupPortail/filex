-- 
-- quota
--
ALTER TABLE quota ADD COLUMN description VARCHAR(50) AFTER name;
UPDATE quota SET description = name;
ALTER TABLE quota DROP COLUMN name;

--
-- big_brother
--
ALTER TABLE big_brother ADD COLUMN description VARCHAR(50) AFTER name;
UPDATE big_brother SET description = name;
ALTER TABLE big_brother DROP COLUMN name;

--
-- exclude
--
ALTER TABLE exclude ADD COLUMN description VARCHAR(50) AFTER name;
ALTER TABLE exclude ADD COLUMN reason VARCHAR(255) AFTER description;
UPDATE exclude SET description = name;
ALTER TABLE exclude DROP COLUMN name;
