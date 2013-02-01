/**
 * Quota.java
 *
 * This file was auto-generated from WSDL
 * by the Apache Axis 1.3 Oct 05, 2005 (05:23:37 EDT) WSDL2Java emitter.
 */

package FILEX;

public class Quota  implements java.io.Serializable {
    private int max_file_size;

    private int max_used_space;

    public Quota() {
    }

    public Quota(
           int max_file_size,
           int max_used_space) {
           this.max_file_size = max_file_size;
           this.max_used_space = max_used_space;
    }


    /**
     * Gets the max_file_size value for this Quota.
     * 
     * @return max_file_size
     */
    public int getMax_file_size() {
        return max_file_size;
    }


    /**
     * Sets the max_file_size value for this Quota.
     * 
     * @param max_file_size
     */
    public void setMax_file_size(int max_file_size) {
        this.max_file_size = max_file_size;
    }


    /**
     * Gets the max_used_space value for this Quota.
     * 
     * @return max_used_space
     */
    public int getMax_used_space() {
        return max_used_space;
    }


    /**
     * Sets the max_used_space value for this Quota.
     * 
     * @param max_used_space
     */
    public void setMax_used_space(int max_used_space) {
        this.max_used_space = max_used_space;
    }

    private java.lang.Object __equalsCalc = null;
    public synchronized boolean equals(java.lang.Object obj) {
        if (!(obj instanceof Quota)) return false;
        Quota other = (Quota) obj;
        if (obj == null) return false;
        if (this == obj) return true;
        if (__equalsCalc != null) {
            return (__equalsCalc == obj);
        }
        __equalsCalc = obj;
        boolean _equals;
        _equals = true && 
            this.max_file_size == other.getMax_file_size() &&
            this.max_used_space == other.getMax_used_space();
        __equalsCalc = null;
        return _equals;
    }

    private boolean __hashCodeCalc = false;
    public synchronized int hashCode() {
        if (__hashCodeCalc) {
            return 0;
        }
        __hashCodeCalc = true;
        int _hashCode = 1;
        _hashCode += getMax_file_size();
        _hashCode += getMax_used_space();
        __hashCodeCalc = false;
        return _hashCode;
    }

    // Type metadata
    private static org.apache.axis.description.TypeDesc typeDesc =
        new org.apache.axis.description.TypeDesc(Quota.class, true);

    static {
        typeDesc.setXmlType(new javax.xml.namespace.QName("urn:FILEX", "quota"));
        org.apache.axis.description.ElementDesc elemField = new org.apache.axis.description.ElementDesc();
        elemField.setFieldName("max_file_size");
        elemField.setXmlName(new javax.xml.namespace.QName("", "max_file_size"));
        elemField.setXmlType(new javax.xml.namespace.QName("http://www.w3.org/2001/XMLSchema", "int"));
        elemField.setNillable(false);
        typeDesc.addFieldDesc(elemField);
        elemField = new org.apache.axis.description.ElementDesc();
        elemField.setFieldName("max_used_space");
        elemField.setXmlName(new javax.xml.namespace.QName("", "max_used_space"));
        elemField.setXmlType(new javax.xml.namespace.QName("http://www.w3.org/2001/XMLSchema", "int"));
        elemField.setNillable(false);
        typeDesc.addFieldDesc(elemField);
    }

    /**
     * Return type metadata object
     */
    public static org.apache.axis.description.TypeDesc getTypeDesc() {
        return typeDesc;
    }

    /**
     * Get Custom Serializer
     */
    public static org.apache.axis.encoding.Serializer getSerializer(
           java.lang.String mechType, 
           java.lang.Class _javaType,  
           javax.xml.namespace.QName _xmlType) {
        return 
          new  org.apache.axis.encoding.ser.BeanSerializer(
            _javaType, _xmlType, typeDesc);
    }

    /**
     * Get Custom Deserializer
     */
    public static org.apache.axis.encoding.Deserializer getDeserializer(
           java.lang.String mechType, 
           java.lang.Class _javaType,  
           javax.xml.namespace.QName _xmlType) {
        return 
          new  org.apache.axis.encoding.ser.BeanDeserializer(
            _javaType, _xmlType, typeDesc);
    }

}
