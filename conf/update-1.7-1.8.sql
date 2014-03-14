--
-- Table des utilisateurs shibboleth
--
CREATE TABLE shib_user (
	id VARCHAR(255) NOT NULL,
	mail TEXT,
	real_name TEXT,
	PRIMARY KEY (id)
) Type=InnoDB;
