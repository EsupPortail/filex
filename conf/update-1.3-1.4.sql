--
-- table upload
--

-- owner_uniq_id
ALTER TABLE upload ADD COLUMN owner_uniq_id VARCHAR(255) NOT NULL;
ALTER TABLE upload ADD INDEX idx_owner_uniq_id (owner_uniq_id);
ALTER TABLE upload ADD INDEX idx_owner (owner);

--
-- big_brother
--
CREATE TABLE big_brother (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
  name VARCHAR(50) NOT NULL UNIQUE,
  enable BOOL DEFAULT 1,
  norder INT DEFAULT 1,
  create_date DATETIME NOT NULL,
  mail VARCHAR(255) NOT NULL,
  PRIMARY KEY (id),
  INDEX idx_rule_id (rule_id),
  CONSTRAINT fk_rule_notify_id FOREIGN KEY (rule_id) REFERENCES rules(id) ON DELETE CASCADE
) Type=InnoDB;
