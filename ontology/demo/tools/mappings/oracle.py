"""Oracle E-Business Suite -> ontology mapping (curated).

Tables (from the main generator's OracleEBSGenerator):
  HZ_PARTIES           -> ora:Party            (TCA party: customer/person/org)
  AP_SUPPLIERS         -> ora:Supplier
  MTL_SYSTEM_ITEMS_B   -> ora:InventoryItem
  OE_ORDER_HEADERS_ALL -> ora:SalesOrder       (SOLD_TO_ORG_ID -> Party)
  OE_ORDER_LINES_ALL   -> ora:SalesOrderLine   (HEADER_ID -> SalesOrder)
  AP_INVOICES_ALL      -> ora:PayablesInvoice  (VENDOR_ID -> Supplier)
  RA_CUSTOMER_TRX_ALL  -> ora:ReceivablesInvoice (BILL_TO_CUSTOMER_ID -> Party)
  GL_JE_LINES          -> ora:JournalLine
"""
from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap

SPEC = MappingSpec(
    system="oracle",
    namespace_prefix="ora",
    tables=[
        TableMap(
            table="HZ_PARTIES", class_iri="ora:Party", uid_prefix="ORA-PARTY", key="PARTY_ID",
            label="PARTY_NAME",
            literals=[
                PropMap("PARTY_NAME", "schema:name"),
                PropMap("PARTY_TYPE", "ora:partyType"),
                PropMap("STATUS", "ora:status"),
                PropMap("CATEGORY_CODE", "ora:categoryCode"),
                PropMap("CITY", "schema:addressLocality"),
                PropMap("STATE", "schema:addressRegion"),
                PropMap("DUNS_NUMBER", "ora:dunsNumber"),
            ],
        ),
        TableMap(
            table="AP_SUPPLIERS", class_iri="ora:Supplier", uid_prefix="ORA-SUPP", key="VENDOR_ID",
            label="VENDOR_NAME",
            literals=[
                PropMap("VENDOR_NAME", "schema:name"),
                PropMap("SEGMENT1", "ora:vendorNumber"),
                PropMap("VENDOR_TYPE_LOOKUP_CODE", "ora:vendorType"),
                PropMap("ENABLED_FLAG", "ora:enabledFlag"),
                PropMap("PAYMENT_METHOD_LOOKUP_CODE", "ora:paymentMethod"),
            ],
        ),
        TableMap(
            table="MTL_SYSTEM_ITEMS_B", class_iri="ora:InventoryItem", uid_prefix="ORA-ITEM",
            key="INVENTORY_ITEM_ID", label="DESCRIPTION",
            literals=[
                PropMap("DESCRIPTION", "schema:name"),
                PropMap("SEGMENT1", "ora:itemNumber"),
                PropMap("ITEM_TYPE", "ora:itemType"),
                PropMap("PRIMARY_UOM_CODE", "ora:primaryUom"),
                PropMap("LIST_PRICE_PER_UNIT", "ora:listPrice", "xsd:decimal"),
                PropMap("UNIT_WEIGHT", "ora:unitWeight", "xsd:decimal"),
            ],
        ),
        TableMap(
            table="OE_ORDER_HEADERS_ALL", class_iri="ora:SalesOrder", uid_prefix="ORA-SO",
            key="HEADER_ID", label=lambda r: f"Sales Order {r.get('ORDER_NUMBER')}",
            literals=[
                PropMap("ORDER_NUMBER", "ora:orderNumber"),
                PropMap("ORDERED_DATE", "ora:orderedDate"),
                PropMap("FLOW_STATUS_CODE", "ora:flowStatus"),
                PropMap("TRANSACTIONAL_CURR_CODE", "ora:currency"),
                PropMap("BOOKED_FLAG", "ora:bookedFlag"),
            ],
            edges=[EdgeMap("SOLD_TO_ORG_ID", "ora:soldToParty", "HZ_PARTIES")],
        ),
        TableMap(
            table="OE_ORDER_LINES_ALL", class_iri="ora:SalesOrderLine", uid_prefix="ORA-SOL",
            key="LINE_ID", label="ORDERED_ITEM",
            literals=[
                PropMap("ORDERED_ITEM", "schema:name"),
                PropMap("ORDERED_QUANTITY", "ora:orderedQuantity", "xsd:decimal"),
                PropMap("ORDER_QUANTITY_UOM", "ora:uom"),
                PropMap("UNIT_SELLING_PRICE", "ora:unitSellingPrice", "xsd:decimal"),
                PropMap("FLOW_STATUS_CODE", "ora:flowStatus"),
            ],
            edges=[EdgeMap("HEADER_ID", "ora:partOfOrder", "OE_ORDER_HEADERS_ALL")],
        ),
        TableMap(
            table="AP_INVOICES_ALL", class_iri="ora:PayablesInvoice", uid_prefix="ORA-API",
            key="INVOICE_ID", label=lambda r: f"AP Invoice {r.get('INVOICE_NUM')}",
            literals=[
                PropMap("INVOICE_NUM", "ora:invoiceNumber"),
                PropMap("INVOICE_DATE", "ora:invoiceDate"),
                PropMap("INVOICE_AMOUNT", "ora:invoiceAmount", "xsd:decimal"),
                PropMap("INVOICE_CURRENCY_CODE", "ora:currency"),
                PropMap("APPROVAL_STATUS", "ora:approvalStatus"),
            ],
            edges=[EdgeMap("VENDOR_ID", "ora:billedBySupplier", "AP_SUPPLIERS")],
        ),
        TableMap(
            table="RA_CUSTOMER_TRX_ALL", class_iri="ora:ReceivablesInvoice", uid_prefix="ORA-ARI",
            key="CUSTOMER_TRX_ID", label=lambda r: f"AR Invoice {r.get('TRX_NUMBER')}",
            literals=[
                PropMap("TRX_NUMBER", "ora:invoiceNumber"),
                PropMap("TRX_DATE", "ora:invoiceDate"),
                PropMap("INVOICE_CURRENCY_CODE", "ora:currency"),
                PropMap("STATUS_TRX", "ora:status"),
            ],
            edges=[EdgeMap("BILL_TO_CUSTOMER_ID", "ora:billedToParty", "HZ_PARTIES")],
        ),
        TableMap(
            table="GL_JE_LINES", class_iri="ora:JournalLine", uid_prefix="ORA-GL",
            key="JE_HEADER_ID", label=lambda r: f"Journal {r.get('PERIOD_NAME')} line {r.get('JE_LINE_NUM')}",
            literals=[
                PropMap("PERIOD_NAME", "ora:periodName"),
                PropMap("EFFECTIVE_DATE", "ora:effectiveDate"),
                PropMap("ENTERED_DR", "ora:enteredDr", "xsd:decimal"),
                PropMap("ENTERED_CR", "ora:enteredCr", "xsd:decimal"),
                PropMap("CURRENCY_CODE", "ora:currency"),
                PropMap("STATUS", "ora:status"),
                PropMap("DESCRIPTION", "schema:name"),
            ],
        ),
    ],
)
