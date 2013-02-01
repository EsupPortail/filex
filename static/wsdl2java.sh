#!/bin/sh
LIB_PREFIX="/home/ofranco/projets/E-SUP/Quotas/test/"
java -classpath $LIB_PREFIX/java/lib/axis-1_3/lib/axis.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/log4j-1.2.8.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/commons-logging-1.0.4.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/commons-discovery-0.2.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/jaxrpc.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/wsdl4j-1.5.1.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/axis-schema.jar:$LIB_PREFIX/java/lib/axis-1_3/lib/saaj.jar org.apache.axis.wsdl.WSDL2Java $1
