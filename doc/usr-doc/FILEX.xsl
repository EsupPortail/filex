<?xml version="1.0" encoding="iso-8859-1"?>
<!-- 
pod2xml generate docroot with default namespace prefix to "http://axkit.org/ns/2000/pod2xml" so
we need to define a prefix for this namespace and access element with this prefix.
-->
<xsl:stylesheet 
	xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"
	xmlns:pod="http://axkit.org/ns/2000/pod2xml"
	exclude-result-prefixes="pod">
	<!-- <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
	"http://www.w3.org/TR/html4/strict.dtd"> -->
	<xsl:output 
		doctype-public="-//W3C//DTD HTML 4.01//EN"
		doctype-system="http://www.w3.org/TR/html4/strict.dtd"
		encoding="ISO-8859-1" 
		method="html" 
		indent="yes"
		version="4.01"/>

	<!-- css file -->
	<xsl:param name="csspath"/>
	<!-- generate TOC -->
	<xsl:param name="gentoc"/>
	<!-- max level -->
	<xsl:variable name="max_level">4</xsl:variable>

	<!-- <pod xmlns="http://axkit.org/ns/2000/pod2xml"> -->
	<xsl:template match="pod:pod">
		<html>
			<head>
				<title>Aide</title>
				<!-- CSS stylesheet -->
				<xsl:element name="link">
					<xsl:attribute name="href"><xsl:value-of select="$csspath"/></xsl:attribute>
					<xsl:attribute name="rel">stylesheet</xsl:attribute>
					<xsl:attribute name="type">text/css</xsl:attribute>
				</xsl:element>
			</head>
			<body>
				<div class="body" id="up">
					<xsl:if test="$gentoc &gt; 0">
						<h1>Sommaire</h1>
						<xsl:call-template name="table_of_content">
							<xsl:with-param name="level">1</xsl:with-param>
							<xsl:with-param name="node" select="."/>
						</xsl:call-template>
					<hr/>
					</xsl:if>
					<xsl:apply-templates/>
				</div>
			</body>
		</html>
	</xsl:template>

	<!-- head -->
	<!-- <xsl:template match="pod:head">
		<head2><xsl:apply-templates/></head2>
	</xsl:template>-->

	<!-- discard pod:title element -->
	<xsl:template match="pod:title"/>
	<!-- discard pod:head element -->
	<xsl:template match="pod:head"/>

	<!-- sect1 => h1 -->
	<xsl:template match="pod:sect1">
		<xsl:element name="h1">
			<xsl:attribute name="id"><xsl:value-of select="generate-id(.)"/></xsl:attribute>
			<xsl:number level="multiple" format="1.1.1.1 " count="//*[starts-with(name(),'sect')]"/>
			<xsl:value-of select="./pod:title"/>
		</xsl:element>
		<xsl:apply-templates/>
		<a href="#up" title="Retour en haut de page" class="linkup">[haut]</a>
	</xsl:template>

	<!-- sect2 => h2 -->
	<xsl:template match="pod:sect2">
		<xsl:element name="h2">
			<xsl:attribute name="id"><xsl:value-of select="generate-id(.)"/></xsl:attribute>
			<xsl:number level="multiple" format="1.1.1.1 " count="//*[starts-with(name(),'sect')]"/>
			<xsl:value-of select="./pod:title"/>
		</xsl:element>
		<xsl:apply-templates/>
	</xsl:template>

	<!-- sect3 => h3 -->
	<xsl:template match="pod:sect3">
		<xsl:element name="h3">
			<xsl:attribute name="id"><xsl:value-of select="generate-id(.)"/></xsl:attribute>
			<xsl:number level="multiple" format="1.1.1.1 " count="//*[starts-with(name(),'sect')]"/>
			<xsl:value-of select="./pod:title"/>
		</xsl:element>
		<xsl:apply-templates/>
	</xsl:template>

	<!-- sect4 => h4 -->
	<xsl:template match="pod:sect4">
		<xsl:element name="h4">
			<xsl:attribute name="id"><xsl:value-of select="generate-id(.)"/></xsl:attribute>
			<xsl:number level="multiple" format="1.1.1.1 " count="//*[starts-with(name(),'sect')]"/>
			<xsl:value-of select="./pod:title"/>
		</xsl:element>
		<xsl:apply-templates/>
	</xsl:template>

	<!-- para => p -->
	<xsl:template match="pod:para">
		<p><xsl:apply-templates/></p> 
	</xsl:template>

	<!--strong => bold -->
	<xsl:template match="pod:strong">
		<strong><xsl:apply-templates/></strong>
	</xsl:template>

	<!-- emphasis -->
	<xsl:template match="pod:emphasis">
		<em><xsl:apply-templates/></em>
	</xsl:template>

	<!-- list -->
	<xsl:template match="pod:list">
		<ul><xsl:apply-templates/></ul>
	</xsl:template>

	<!-- item|itemtext -->
	<xsl:template match="pod:item">
		<li><xsl:apply-templates/></li>
	</xsl:template>

	<xsl:template match="pod:itemtext">
		<!-- if pod:itemtext is the only element then nothing -->
		<!-- if pod:itemtext if followed by a para then underline -->
		<!-- get parent child count -->
		<xsl:variable name="cpchild" select="count(./../child::*)"/>
		<xsl:choose>
			<xsl:when test="$cpchild &gt; 1">
				<span class="underline"><xsl:apply-templates/></span>
			</xsl:when>
			<xsl:otherwise><xsl:apply-templates/></xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<!-- Generate table of content -->
	<xsl:template name="table_of_content">
		<xsl:param name="level"/>
		<xsl:param name="node"/>
		<xsl:variable name="nextlevel" select="$level+1"/>
		<xsl:variable name="sectname" select="concat('sect',$level)"/>
		<xsl:variable name="can_go" select="count($node/child::*[starts-with(name(),'sect')])"/>
		<xsl:if test="$level &lt;= $max_level and $can_go &gt; 0">
			<ol>
				<!-- search for child who's name == $sectname -->
				<xsl:for-each select="$node/child::*[name() = $sectname]">
					<li>
						<xsl:element name="a">
							<xsl:attribute name="href"><xsl:value-of select="concat('#',generate-id(.))"/></xsl:attribute>
							<xsl:attribute name="title">allez à ...</xsl:attribute>
							<xsl:value-of select="./pod:title"/>
						</xsl:element>
						<xsl:call-template name="table_of_content">
							<xsl:with-param name="level" select="$nextlevel"/>
							<xsl:with-param name="node" select="."/>
						</xsl:call-template>
					</li>
				</xsl:for-each>
			</ol>
		</xsl:if>
	</xsl:template>
</xsl:stylesheet>
