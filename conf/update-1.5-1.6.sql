--
-- rules
-- 

--
-- supprimer l'index d'unicité de la colonne "exp"
--
ALTER TABLE rules DROP INDEX exp;
--
-- créer une constrainte d'unicité sur type+exp
--
ALTER TABLE rules ADD CONSTRAINT UN_TYPE_EXP UNIQUE (type,exp);
