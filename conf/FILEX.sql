-- MySQL dump 9.11
--
-- Host: localhost    Database: FILEX
-- ------------------------------------------------------
-- Server version	4.0.20

--
-- Current Database: FILEX
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ FILEX;

--
-- Créer l'utilisateur
--

GRANT ALL PRIVILEGES ON FILEX.* TO 'FILEX'@'localhost' IDENTIFIED BY 'FileX';

--
-- utiliser la base
--

USE FILEX;

--
-- Table des fichiers déposés
--
-- id = clef primaire
-- real_name = nom réel du fichier
-- file_name = nom du fichier sur le disque
-- file_size = taille du fichier en octets
-- upload_date = date où le fichier à été déposé
-- expire_date = date d'expiration du fichier
-- owner = propriétaire du fichier (ldap uid)
-- content_type = type MIME du fichier (donné par le navigateur)
-- enable = 1: le fichier peut être téléchargé, 0: le fichier ne peut être téléchargé même si pas expiré
-- deleted = 1: le fichier a été supprimé du disque 
-- get_delivery = 1: recevoir un mail de notification à chaque téléchargement
-- get_resume = 1: recevoir un mail de résumé à la suppression du fichier
-- ip_adress = adresse ip lors du téléchargement
-- use_proxy = un proxy à t-il été utilisé
-- proxy_infos = information de proxy si proxy utilisé
-- renew_count = nombre de fois où l'expiration du fichier a été renouvellée
-- with_password = besoin d'un mot de passe pout le téléchargement
-- password = mot de passe pour le téléchargement
-- user_agent = identifiant navigateur
CREATE TABLE upload (
  id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  real_name VARCHAR(255) NOT NULL,
  file_name VARCHAR(30) NOT NULL UNIQUE,
  file_size BIGINT(20) NOT NULL, 
  upload_date DATETIME NOT NULL,
  expire_date DATETIME NOT NULL,
  owner VARCHAR(255) NOT NULL, 
  content_type VARCHAR(255) DEFAULT 'application/octet-stream',
  enable BOOL NOT NULL DEFAULT 1,
  deleted BOOL NOT NULL DEFAULT 0,
  get_delivery BOOL NOT NULL DEFAULT 1,
  get_resume BOOL NOT NULL DEFAULT 0,
	ip_address VARCHAR(15) DEFAULT NULL,
	use_proxy BOOL NOT NULL DEFAULT 0,
	proxy_infos VARCHAR(255) DEFAULT NULL,
	renew_count INT UNSIGNED NOT NULL DEFAULT 0,
	with_password BOOL NOT NULL DEFAULT 0,
	password VARCHAR(32) DEFAULT NULL,
	user_agent VARCHAR(255) DEFAULT NULL,
	owner_uniq_id VARCHAR(255) NOT NULL,
  PRIMARY KEY  (id),
  INDEX idx_filename (file_name),
  INDEX idx_expire (expire_date),
	INDEX idx_owner (owner),
	INDEX idx_owner_uniq_id (owner_uniq_id),
) TYPE=InnoDB;


--
-- Table des téléchargements courants
--
-- download_id = identifiant de l'enregistrement 
-- upload_id = reference depuis la table upload
-- start_date = date de début du téléchargement
-- ip_address = adresse ip du client

CREATE TABLE current_download (
  download_id VARCHAR(30) NOT NULL UNIQUE,
  upload_id BIGINT(20) UNSIGNED NOT NULL,
  start_date DATETIME NOT NULL,
  ip_address VARCHAR(15) NOT NULL,
  INDEX idx_upload_id (upload_id),
  CONSTRAINT fk_cd_upload_id FOREIGN KEY (upload_id) REFERENCES upload (id) ON DELETE CASCADE
) TYPE=InnoDB;

--
-- Table des téléchargements
--
-- get_id = clef primaire
-- upload_id = reference du fichier depuis la table "upload"
-- ip_address = adresse ip du client
-- use_proxy = le client est derrière un proxy
-- date = date du téléchargement
-- canceled = téléchagement a été annulé
-- proxy_info =^information de proxy du client
-- user_agent = identifiant navigateur
-- admin_download = téléchargement "administratif"
CREATE TABLE get (
  get_id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  upload_id BIGINT(20) UNSIGNED NOT NULL,
  ip_address CHAR(15) NOT NULL, 
  use_proxy BOOL NOT NULL DEFAULT 0,
  date DATETIME NOT NULL,
  canceled BOOL NULL DEFAULT 0,
  proxy_infos VARCHAR(255) DEFAULT NULL,
	user_agent VARCHAR(255) DEFAULT NULL,
	admin_download BOOL NOT NULL DEFAULT 0,
  PRIMARY KEY  (get_id),
  INDEX idx_upload_id (upload_id),
  CONSTRAINT fk_upload_id FOREIGN KEY (upload_id) REFERENCES upload (id) ON DELETE CASCADE
) TYPE=InnoDB;

--
-- Table des administrateurs du système
--
-- id = clef primaire
-- uid =  login de l'utilisateur
-- enable = [0|1] utilisateur activé ou non

CREATE TABLE usr_admin (
  id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  uid VARCHAR(255) NOT NULL UNIQUE, 
  enable BOOL NOT NULL DEFAULT 1,
  PRIMARY KEY  (id)
) TYPE=InnoDB;

--
-- Ne pas oublié d'insérer au moins un administrateur
--

INSERT INTO usr_admin VALUES (1,'ldap_uid',1);

--
-- Table des règles
--
-- Description : table des règles utilisées pour les exclusions et les quotas
--
-- id = clef primaire
-- exp = contenu de la règle
-- name = nom de la règle
-- type = type de règle
-- 
CREATE TABLE rules (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	exp VARCHAR(255) NOT NULL,
	name VARCHAR(50) NOT NULL UNIQUE,
	type INT NOT NULL DEFAULT 1,
	PRIMARY KEY (id),
	UNIQUE (type,exp)
) Type=InnoDB;

--
-- Table des exclusions
--
-- Description : table des règles d'exclusion 
--
-- id = clef primaire
-- rule_id = règle de référence
-- description = description de la règle
-- enable = activé ou non (0|1)
-- rorder = ordre d'application de la règle
-- create-date = date de création de la règle
-- 
CREATE TABLE exclude (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
	description VARCHAR(50),
	reason VARCHAR(255),
	enable BOOL DEFAULT 1,
	rorder INT DEFAULT 1,
  create_date DATETIME NOT NULL,
	PRIMARY KEY (id),
	INDEX idx_rule_id (rule_id),
	CONSTRAINT fk_rule_exclude_id FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
) Type=InnoDB;

--
-- Table des Quotas
--
-- Description : table des règles de quota
--
-- id = clef primaire
-- rule_id = règle de référence
-- description = description de la règle
-- enable = activé ou non
-- qorder = ordre d'application de la règle
-- create_date = date de création de la règle

CREATE TABLE quota (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
	description VARCHAR(50),
	enable BOOL DEFAULT 1,
	qorder INT DEFAULT 1,
	create_date DATETIME NOT NULL,
	max_file_size BIGINT NOT NULL DEFAULT 0,
	max_used_space BIGINT NOT NULL DEFAULT 0,
	PRIMARY KEY (id),
	INDEX idx_rule_id (rule_id),
	CONSTRAINT fk_rule_quota_id FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
) Type=InnoDB;

--
--
--
--
CREATE TABLE big_brother (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
	description VARCHAR(50),
	enable BOOL DEFAULT 1,
	norder INT DEFAULT 1,
	create_date DATETIME NOT NULL,
	mail VARCHAR(255) NOT NULL,
	PRIMARY KEY (id),
	INDEX idx_rule_id (rule_id),
	CONSTRAINT fk_rule_notify_id FOREIGN KEY (rule_id) REFERENCES rules(id) ON DELETE CASCADE
) Type=InnoDB;
