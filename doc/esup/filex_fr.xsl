<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:output method="xml" 
		encoding="utf-8"
		indent="yes"/>

	<!-- begin here -->
	<xsl:template match="/filex">
		<h1 class="uportal-channel-subtitle">Résumé de vos fichiers encore valides sur <a href="http://filex.domain.fr" target="_blank" title="Accès à FILEX">FILEX</a></h1>
		<p class="uportal-channel-text">Par défaut, vos fichiers sont triés de manière décroissante sur la date de dépose.<br/>
Vous pouvez les trier selon différent critères en cliquant sur <strong>+</strong> ou <strong>-</strong> dans les entêtes de colonnes.</p>
		<p class="uportal-channel-text">Pour accéder aux informations de vos fichiers; cliquez sur les noms de ceux-ci</p>
		<xsl:apply-templates select="./error"/>
		<xsl:apply-templates select="./uploads"/>
	</xsl:template>

	<!-- uploads -->
	<xsl:template match="uploads">
		<table cellpadding="5pt" cellspacing="0" width="100%" summary="Liste de vos fichiers encore valides" class="uportal-channel-text">
			<caption class="uportal-channel-table-caption"><xsl:call-template name="caption"><xsl:with-param name="node" select="."/></xsl:call-template></caption>
			<thead class="uportal-channel-table-header">
				<tr class="uportal-background-med">
					<td><xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_name_asc</xsl:with-param>
							<xsl:with-param name="text">+</xsl:with-param>
							<xsl:with-param name="title">Tri croissant sur les noms</xsl:with-param>
							</xsl:call-template> Nom <xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_name_desc</xsl:with-param>
							<xsl:with-param name="text">-</xsl:with-param>
							<xsl:with-param name="title">Tri décroissant sur les noms</xsl:with-param>
							</xsl:call-template>
					</td>
					<td><xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_size_asc</xsl:with-param>
							<xsl:with-param name="text">+</xsl:with-param>
							<xsl:with-param name="title">Tri croissant sur la taille</xsl:with-param>
							</xsl:call-template> Taille <xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_size_desc</xsl:with-param>
							<xsl:with-param name="text">-</xsl:with-param>
							<xsl:with-param name="title">Tri décroissant sur la taille</xsl:with-param>
							</xsl:call-template></td>
					<td><xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_upload_date_asc</xsl:with-param>
							<xsl:with-param name="text">+</xsl:with-param>
							<xsl:with-param name="title">Tri croissant sur la date de dépose</xsl:with-param>
							</xsl:call-template> Déposé le <xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_upload_date_desc</xsl:with-param>
							<xsl:with-param name="text">-</xsl:with-param>
							<xsl:with-param name="title">Tri décroissant sur la date de dépose</xsl:with-param>
							</xsl:call-template></td>
					<td><xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_expire_date_asc</xsl:with-param>
							<xsl:with-param name="text">+</xsl:with-param>
							<xsl:with-param name="title">Tri croissant sur la date d'expiration</xsl:with-param>
							</xsl:call-template> Expire le <xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_expire_date_desc</xsl:with-param>
							<xsl:with-param name="text">-</xsl:with-param>
							<xsl:with-param name="title">Tri décroissant sur la date d'expiration</xsl:with-param>
							</xsl:call-template></td>
					<td><xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_download_count_asc</xsl:with-param>
							<xsl:with-param name="text">+</xsl:with-param>
							<xsl:with-param name="title">Tri croissant sur le nombre de téléchargement</xsl:with-param>
							</xsl:call-template> Téléchargé <xsl:call-template name="gen_sort_url">
							<xsl:with-param name="node" select="./sorts"/>
							<xsl:with-param name="name">sort_download_count_desc</xsl:with-param>
							<xsl:with-param name="text">-</xsl:with-param>
							<xsl:with-param name="title">Tri décroissant sur le nombre de téléchargement</xsl:with-param>
							</xsl:call-template></td>
				</tr>
			</thead>
			<tbody>
			<xsl:choose>
				<xsl:when test="@active_files_count &gt; 0">
					<xsl:for-each select="./upload">
					<xsl:variable name="odd" select="position()"/>
				<xsl:element name="tr">
					<xsl:choose>
						<xsl:when test="$odd mod 2 = 0">
							<xsl:attribute name="class">uportal-background-med</xsl:attribute> 
						</xsl:when>
						<xsl:otherwise>
							<xsl:attribute name="class">uportal-background-light</xsl:attribute> 
						</xsl:otherwise>
					</xsl:choose>
					<td><xsl:call-template name="make_link"><xsl:with-param name="url" select="@url"/><xsl:with-param name="name" select="@name"/></xsl:call-template></td>
					<td><xsl:value-of select="@size"/></td>
					<td><xsl:value-of select="@upload_date"/></td>
					<td><xsl:value-of select="@expire_date"/></td>
					<td><xsl:value-of select="@download_count"/></td>
				</xsl:element>
			</xsl:for-each>
				</xsl:when>
				<xsl:otherwise>
				<tr><td colspan="5"><strong>Vous n'avez pas de fichier non expirés</strong></td></tr>
				</xsl:otherwise>
			</xsl:choose>
			</tbody>
		</table>
	</xsl:template>

	<!-- create sort url -->
	<xsl:template name="gen_sort_url">
		<xsl:param name="node"/>
		<xsl:param name="name"/>
		<xsl:param name="text"/>
		<xsl:param name="title"/>
		<xsl:if test="$node">
			<xsl:if test="$node/sort[@name=$name]">
			<xsl:element name="a">
				<xsl:attribute name="href">
					<xsl:call-template name="add_cw_inChannelLink">
						<xsl:with-param name="url" select="$node/sort[@name=$name]/@url"/>
					</xsl:call-template>
				</xsl:attribute>
				<xsl:attribute name="title"><xsl:value-of select="$title"/></xsl:attribute>
				<xsl:value-of select="$text"/>
			</xsl:element>
			</xsl:if>
		</xsl:if>
	</xsl:template>

	<!-- cw_inChannelLink=true -->
	<xsl:template name="add_cw_inChannelLink">
		<xsl:param name="url"/>
		<!-- check if containing ? -->
		<xsl:choose>
			<xsl:when test="contains($url,'?')">
				<xsl:value-of select="concat($url,'&amp;','cw_inChannelLink=true')"/>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="concat($url,'?','cw_inChannelLink=true')"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
	<!-- create upload link --> 
	<xsl:template name="make_link">
		<xsl:param name="url"/>
		<xsl:param name="name"/>
		<xsl:element name="a">
			<xsl:attribute name="href"><xsl:value-of select="$url"/></xsl:attribute>
			<xsl:attribute name="title">Information sur le fichier</xsl:attribute>
			<xsl:attribute name="target">_blank</xsl:attribute>
			<xsl:value-of select="$name"/>
		</xsl:element>
	</xsl:template>
	<!-- table caption -->
	<xsl:template name="caption">
		<xsl:param name="node"/>
		<xsl:text>Fichiers actifs : </xsl:text><xsl:value-of select="$node/@active_files_count"/>
		<xsl:text>, Espace Utilisé : </xsl:text><xsl:value-of select="$node/@used_space"/>
		<xsl:if test="@max_used_space">
		<xsl:text> / </xsl:text><strong><xsl:value-of select="$node/@max_used_space"/></strong>
		</xsl:if>
	</xsl:template>

	<!-- error -->
	<xsl:template match="error">
	<p>Une erreur c'est produite : <xsl:value-of select="."/></p>
	</xsl:template>
</xsl:stylesheet>
