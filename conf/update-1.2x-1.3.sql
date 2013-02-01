--
-- table upload
--

-- user_agent
ALTER TABLE upload ADD COLUMN user_agent VARCHAR(255) DEFAULT NULL;

--
-- download
--

-- user_agent
ALTER TABLE get ADD COLUMN user_agent VARCHAR(255) DEFAULT NULL;

-- administrative download
ALTER TABLE get ADD COLUMN admin_download BOOL NOT NULL DEFAULT 0;
