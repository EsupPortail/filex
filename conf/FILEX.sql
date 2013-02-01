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
-- Cr�er l'utilisateur
--

GRANT ALL PRIVILEGES ON FILEX.* TO 'FILEX'@'localhost' IDENTIFIED BY 'FileX';

--
-- utiliser la base
--

USE FILEX;

--
-- Table des fichiers d�pos�s
--
-- id = clef primaire
-- real_name = nom r�el du fichier
-- file_name = nom du fichier sur le disque
-- file_size = taille du fichier en octets
-- upload_date = date o� le fichier � �t� d�pos�
-- expire_date = date d'expiration du fichier
-- owner = propri�taire du fichier (ldap uid)
-- content_type = type MIME du fichier (donn� par le navigateur)
-- enable = 1: le fichier peut �tre t�l�charg�, 0: le fichier ne peut �tre t�l�charg� m�me si pas expir�
-- deleted = 1: le fichier a �t� supprim� du disque 
-- get_delivery = 1: recevoir un mail de notification � chaque t�l�chargement
-- get_resume = 1: recevoir un mail de r�sum� � la suppression du fichier
-- ip_adress = adresse ip lors du t�l�chargement
-- use_proxy = un proxy � t-il �t� utilis�
-- proxy_infos = information de proxy si proxy utilis�
-- renew_count = nombre de fois o� l'expiration du fichier a �t� renouvell�e
-- with_password = besoin d'un mot de passe pout le t�l�chargement
-- password = mot de passe pour le t�l�chargement
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
  PRIMARY KEY  (id),
  INDEX idx_filename (file_name),
  INDEX idx_expire (expire_date)
) TYPE=InnoDB;


--
-- Table des t�l�chargements courants
--
-- download_id = identifiant de l'enregistrement 
-- upload_id = reference depuis la table upload
-- start_date = date de d�but du t�l�chargement
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
-- Table des t�l�chargements
--
-- get_id = clef primaire
-- upload_id = reference du fichier depuis la table "upload"
-- ip_address = adresse ip du client
-- use_proxy = le client est derri�re un proxy
-- date = date du t�l�chargement
-- canceled = t�l�chagement a �t� annul�
-- proxy_info =^information de proxy du client

CREATE TABLE get (
  get_id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  upload_id BIGINT(20) UNSIGNED NOT NULL,
  ip_address CHAR(15) NOT NULL, 
  use_proxy BOOL NOT NULL DEFAULT 0,
  date DATETIME NOT NULL,
  canceled BOOL NULL DEFAULT 0,
  proxy_infos VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY  (get_id),
  INDEX idx_upload_id (upload_id),
  CONSTRAINT fk_upload_id FOREIGN KEY (upload_id) REFERENCES upload (id) ON DELETE CASCADE
) TYPE=InnoDB;

--
-- Table des administrateurs du syst�me
--
-- id = clef primaire
-- uid =  login de l'utilisateur
-- enable = [0|1] utilisateur activ� ou non

CREATE TABLE usr_admin (
  id BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  uid VARCHAR(255) NOT NULL UNIQUE, 
  enable BOOL NOT NULL DEFAULT 1,
  PRIMARY KEY  (id)
) TYPE=InnoDB;

--
-- Ne pas oubli� d'ins�rer au moins un administrateur
--

INSERT INTO usr_admin VALUES (1,'ldap_uid',1);

--
-- Table des r�gles
--
-- Description : table des r�gles utilis�es pour les exclusions et les quotas
--
-- id = clef primaire
-- exp = contenu de la r�gle
-- name = nom de la r�gle
-- type = type de r�gle
-- 
CREATE TABLE rules (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	exp VARCHAR(255) NOT NULL UNIQUE,
	name VARCHAR(50) NOT NULL UNIQUE,
	type INT NOT NULL DEFAULT 1,
	PRIMARY KEY (id)
) Type=InnoDB;

--
-- Table des exclusions
--
-- Description : table des r�gles d'exclusion 
--
-- id = clef primaire
-- rule_id = r�gle de r�f�rence
-- name = nom de la r�gle
-- enable = activ� ou non (0|1)
-- rorder = ordre d'application de la r�gle
-- create-date = date de cr�ation de la r�gle
-- 
CREATE TABLE exclude (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
	name VARCHAR(50) UNIQUE NOT NULL,
	enable BOOL DEFAULT 1,
	rorder INT DEFAULT 1,
  create_date DATETIME NOT NULL,
	PRIMARY KEY (id),
	INDEX idx_rule_id (rule_id),
	CONSTRAINT fk_rule_id FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
) Type=InnoDB;

--
-- Table des Quotas
--
-- Description : table des r�gles de quota
--
-- id = clef primaire
-- rule_id = r�gle de r�f�rence
-- name = nom de la r�gle
-- enable = activ� ou non
-- qorder = ordre d'application de la r�gle
-- create_date = date de cr�ation de la r�gle

CREATE TABLE quota (
	id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
	rule_id BIGINT UNSIGNED NOT NULL UNIQUE,
	name VARCHAR(50) NOT NULL UNIQUE,
	enable BOOL DEFAULT 1,
	qorder INT DEFAULT 1,
	create_date DATETIME NOT NULL,
	max_file_size BIGINT NOT NULL DEFAULT 0,
	max_used_space BIGINT NOT NULL DEFAULT 0,
	PRIMARY KEY (id),
	INDEX idx_rule_id (rule_id),
	CONSTRAINT fk_rule_id FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
) Type=InnoDB;


