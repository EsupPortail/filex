/**
 * FILEXSoapLocator.java
 *
 * This file was auto-generated from WSDL
 * by the Apache Axis 1.3 Oct 05, 2005 (05:23:37 EDT) WSDL2Java emitter.
 */

package FILEX;

public class FILEXSoapLocator extends org.apache.axis.client.Service implements FILEX.FILEXSoap {

/**
 * unknown
 */

    public FILEXSoapLocator() {
    }


    public FILEXSoapLocator(org.apache.axis.EngineConfiguration config) {
        super(config);
    }

    public FILEXSoapLocator(java.lang.String wsdlLoc, javax.xml.namespace.QName sName) throws javax.xml.rpc.ServiceException {
        super(wsdlLoc, sName);
    }

    // Use to get a proxy class for FILEXPort
    private java.lang.String FILEXPort_address = "http://pc401-189.insa-lyon.fr/soap";

    public java.lang.String getFILEXPortAddress() {
        return FILEXPort_address;
    }

    // The WSDD service name defaults to the port name.
    private java.lang.String FILEXPortWSDDServiceName = "FILEXPort";

    public java.lang.String getFILEXPortWSDDServiceName() {
        return FILEXPortWSDDServiceName;
    }

    public void setFILEXPortWSDDServiceName(java.lang.String name) {
        FILEXPortWSDDServiceName = name;
    }

    public FILEX.FILEXPort getFILEXPort() throws javax.xml.rpc.ServiceException {
       java.net.URL endpoint;
        try {
            endpoint = new java.net.URL(FILEXPort_address);
        }
        catch (java.net.MalformedURLException e) {
            throw new javax.xml.rpc.ServiceException(e);
        }
        return getFILEXPort(endpoint);
    }

    public FILEX.FILEXPort getFILEXPort(java.net.URL portAddress) throws javax.xml.rpc.ServiceException {
        try {
            FILEX.FILEXBindingStub _stub = new FILEX.FILEXBindingStub(portAddress, this);
            _stub.setPortName(getFILEXPortWSDDServiceName());
            return _stub;
        }
        catch (org.apache.axis.AxisFault e) {
            return null;
        }
    }

    public void setFILEXPortEndpointAddress(java.lang.String address) {
        FILEXPort_address = address;
    }

    /**
     * For the given interface, get the stub implementation.
     * If this service has no port for the given interface,
     * then ServiceException is thrown.
     */
    public java.rmi.Remote getPort(Class serviceEndpointInterface) throws javax.xml.rpc.ServiceException {
        try {
            if (FILEX.FILEXPort.class.isAssignableFrom(serviceEndpointInterface)) {
                FILEX.FILEXBindingStub _stub = new FILEX.FILEXBindingStub(new java.net.URL(FILEXPort_address), this);
                _stub.setPortName(getFILEXPortWSDDServiceName());
                return _stub;
            }
        }
        catch (java.lang.Throwable t) {
            throw new javax.xml.rpc.ServiceException(t);
        }
        throw new javax.xml.rpc.ServiceException("There is no stub implementation for the interface:  " + (serviceEndpointInterface == null ? "null" : serviceEndpointInterface.getName()));
    }

    /**
     * For the given interface, get the stub implementation.
     * If this service has no port for the given interface,
     * then ServiceException is thrown.
     */
    public java.rmi.Remote getPort(javax.xml.namespace.QName portName, Class serviceEndpointInterface) throws javax.xml.rpc.ServiceException {
        if (portName == null) {
            return getPort(serviceEndpointInterface);
        }
        java.lang.String inputPortName = portName.getLocalPart();
        if ("FILEXPort".equals(inputPortName)) {
            return getFILEXPort();
        }
        else  {
            java.rmi.Remote _stub = getPort(serviceEndpointInterface);
            ((org.apache.axis.client.Stub) _stub).setPortName(portName);
            return _stub;
        }
    }

    public javax.xml.namespace.QName getServiceName() {
        return new javax.xml.namespace.QName("urn:FILEX", "FILEXSoap");
    }

    private java.util.HashSet ports = null;

    public java.util.Iterator getPorts() {
        if (ports == null) {
            ports = new java.util.HashSet();
            ports.add(new javax.xml.namespace.QName("urn:FILEX", "FILEXPort"));
        }
        return ports.iterator();
    }

    /**
    * Set the endpoint address for the specified port name.
    */
    public void setEndpointAddress(java.lang.String portName, java.lang.String address) throws javax.xml.rpc.ServiceException {
        
if ("FILEXPort".equals(portName)) {
            setFILEXPortEndpointAddress(address);
        }
        else 
{ // Unknown Port Name
            throw new javax.xml.rpc.ServiceException(" Cannot set Endpoint Address for Unknown Port" + portName);
        }
    }

    /**
    * Set the endpoint address for the specified port name.
    */
    public void setEndpointAddress(javax.xml.namespace.QName portName, java.lang.String address) throws javax.xml.rpc.ServiceException {
        setEndpointAddress(portName.getLocalPart(), address);
    }

}
