"""SAP S/4HANA -> ontology mapping (curated).

Tables (from the main generator's SAPGenerator):
  KNA1  Customer master         -> sap:Customer
  MARA  Material master         -> sap:Material
  VBAK  Sales order header      -> sap:SalesOrder      (KUNNR -> Customer)
  VBAP  Sales order item        -> sap:SalesOrderItem  (VBELN -> Order, MATNR -> Material)
  LFA1  Vendor master           -> sap:Vendor
  EKKO  Purchase order header   -> sap:PurchaseOrder   (LIFNR -> Vendor)
  BKPF  Accounting document     -> sap:AccountingDocument
  PA0001 HR org assignment      -> sap:Employee
  PA0002 HR personal data       -> sap:Employee (same UID; enriches the worker)
"""
from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap

SPEC = MappingSpec(
    system="sap",
    namespace_prefix="sap",
    tables=[
        TableMap(
            table="KNA1", class_iri="sap:Customer", uid_prefix="SAP-CUST", key="KUNNR",
            label="NAME1",
            literals=[
                PropMap("NAME1", "schema:name"),
                PropMap("SMTP_ADDR", "schema:email"),
                PropMap("ORT01", "schema:addressLocality"),
                PropMap("REGIO", "schema:addressRegion"),
                PropMap("LAND1", "sap:country"),
                PropMap("KTOKD", "sap:accountGroup"),
                PropMap("BRSCH", "sap:industryKey"),
                PropMap("STCEG", "sap:vatNumber"),
            ],
        ),
        TableMap(
            table="MARA", class_iri="sap:Material", uid_prefix="SAP-MAT", key="MATNR",
            label="MAKTX",
            literals=[
                PropMap("MAKTX", "schema:name"),
                PropMap("MTART", "sap:materialType"),
                PropMap("MATKL", "sap:materialGroup"),
                PropMap("MEINS", "sap:baseUnit"),
                PropMap("BRGEW", "sap:grossWeight", "xsd:decimal"),
                PropMap("NTGEW", "sap:netWeight", "xsd:decimal"),
            ],
        ),
        TableMap(
            table="VBAK", class_iri="sap:SalesOrder", uid_prefix="SAP-SO", key="VBELN",
            label=lambda r: f"Sales Order {r.get('VBELN')}",
            literals=[
                PropMap("AUART", "sap:orderType"),
                PropMap("AUDAT", "sap:documentDate"),
                PropMap("NETWR", "sap:netValue", "xsd:decimal"),
                PropMap("WAERK", "sap:currency"),
                PropMap("GBSTK", "sap:overallStatus"),
            ],
            edges=[EdgeMap("KUNNR", "sap:soldToParty", "KNA1")],
        ),
        TableMap(
            table="VBAP", class_iri="sap:SalesOrderItem", uid_prefix="SAP-SOI",
            key=lambda r: f"{r.get('VBELN')}-{r.get('POSNR')}",
            label="ARKTX",
            literals=[
                PropMap("ARKTX", "schema:name"),
                PropMap("KWMENG", "sap:quantity", "xsd:decimal"),
                PropMap("NETWR", "sap:netValue", "xsd:decimal"),
                PropMap("NETPR", "sap:netPrice", "xsd:decimal"),
            ],
            edges=[
                EdgeMap("VBELN", "sap:partOfOrder", "VBAK"),
                EdgeMap("MATNR", "sap:refersToMaterial", "MARA"),
            ],
        ),
        TableMap(
            table="LFA1", class_iri="sap:Vendor", uid_prefix="SAP-VEND", key="LIFNR",
            label="NAME1",
            literals=[
                PropMap("NAME1", "schema:name"),
                PropMap("SMTP_ADDR", "schema:email"),
                PropMap("ORT01", "schema:addressLocality"),
                PropMap("LAND1", "sap:country"),
                PropMap("KTOKK", "sap:accountGroup"),
            ],
        ),
        TableMap(
            table="EKKO", class_iri="sap:PurchaseOrder", uid_prefix="SAP-PO", key="EBELN",
            label=lambda r: f"Purchase Order {r.get('EBELN')}",
            literals=[
                PropMap("BSART", "sap:documentType"),
                PropMap("BEDAT", "sap:documentDate"),
                PropMap("RLWRT", "sap:totalValue", "xsd:decimal"),
                PropMap("WAERS", "sap:currency"),
                PropMap("STATU", "sap:overallStatus"),
            ],
            edges=[EdgeMap("LIFNR", "sap:vendorParty", "LFA1")],
        ),
        TableMap(
            table="BKPF", class_iri="sap:AccountingDocument", uid_prefix="SAP-FI", key="BELNR",
            label=lambda r: f"FI Document {r.get('BELNR')}",
            literals=[
                PropMap("BLART", "sap:documentType"),
                PropMap("BUDAT", "sap:postingDate"),
                PropMap("GJAHR", "sap:fiscalYear"),
                PropMap("WAERS", "sap:currency"),
                PropMap("BKTXT", "schema:name"),
            ],
        ),
        TableMap(
            table="PA0001", class_iri="sap:Employee", uid_prefix="SAP-EMP", key="PERNR",
            label=lambda r: f"Employee {r.get('PERNR')}",
            literals=[
                PropMap("BUKRS", "sap:companyCode"),
                PropMap("WERKS", "sap:plant"),
                PropMap("KOSTL", "sap:costCenter"),
                PropMap("ORGEH", "sap:orgUnit"),
            ],
        ),
        TableMap(
            table="PA0002", class_iri="sap:Employee", uid_prefix="SAP-EMP", key="PERNR",
            label=lambda r: f"{r.get('NACHN')}, {r.get('VORNA')}",
            literals=[
                PropMap("VORNA", "sap:firstName"),
                PropMap("NACHN", "sap:lastName"),
                PropMap("GBDAT", "sap:birthDate"),
                PropMap("NATIO", "sap:nationality"),
            ],
        ),
    ],
)
