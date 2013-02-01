/**
 * FILEXSoap.java
 *
 * This file was auto-generated from WSDL
 * by the Apache Axis 1.3 Oct 05, 2005 (05:23:37 EDT) WSDL2Java emitter.
 */

package FILEX;

public interface FILEXSoap extends javax.xml.rpc.Service {

/**
 * unknown
 */
    public java.lang.String getFILEXPortAddress();

    public FILEX.FILEXPort getFILEXPort() throws javax.xml.rpc.ServiceException;

    public FILEX.FILEXPort getFILEXPort(java.net.URL portAddress) throws javax.xml.rpc.ServiceException;
}
