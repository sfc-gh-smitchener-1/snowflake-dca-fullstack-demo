"""Salesforce -> ontology mapping (curated).

Objects (from the main generator's SalesforceGenerator):
  Account      -> sfdc:Account
  Contact      -> sfdc:Contact      (AccountId -> Account)
  Opportunity  -> sfdc:Opportunity  (AccountId -> Account)
  Case         -> sfdc:Case         (AccountId -> Account, ContactId -> Contact)
  Lead         -> sfdc:Lead
  Product2     -> sfdc:Product
  Campaign     -> sfdc:Campaign
  Task         -> sfdc:Task         (WhatId -> Account, WhoId -> Contact)
"""
from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap

SPEC = MappingSpec(
    system="salesforce",
    namespace_prefix="sfdc",
    tables=[
        TableMap(
            table="Account", class_iri="sfdc:Account", uid_prefix="SFDC-ACC", key="Id",
            label="Name",
            literals=[
                PropMap("Name", "schema:name"),
                PropMap("Industry", "sfdc:industry"),
                PropMap("Type", "sfdc:accountType"),
                PropMap("Rating", "sfdc:rating"),
                PropMap("AnnualRevenue", "sfdc:annualRevenue", "xsd:decimal"),
                PropMap("NumberOfEmployees", "sfdc:numberOfEmployees", "xsd:integer"),
                PropMap("BillingCity", "schema:addressLocality"),
                PropMap("BillingState", "schema:addressRegion"),
                PropMap("Phone", "schema:telephone"),
                PropMap("Website", "schema:url"),
                PropMap("Customer_Segment__c", "sfdc:customerSegment"),
            ],
        ),
        TableMap(
            table="Contact", class_iri="sfdc:Contact", uid_prefix="SFDC-CON", key="Id",
            label=lambda r: f"{r.get('FirstName')} {r.get('LastName')}",
            literals=[
                PropMap("FirstName", "sfdc:firstName"),
                PropMap("LastName", "sfdc:lastName"),
                PropMap("Email", "schema:email"),
                PropMap("Title", "sfdc:title"),
                PropMap("Department", "sfdc:department"),
                PropMap("Phone", "schema:telephone"),
                PropMap("LeadSource", "sfdc:leadSource"),
            ],
            edges=[EdgeMap("AccountId", "sfdc:belongsToAccount", "Account")],
        ),
        TableMap(
            table="Opportunity", class_iri="sfdc:Opportunity", uid_prefix="SFDC-OPP", key="Id",
            label="Name",
            literals=[
                PropMap("Name", "schema:name"),
                PropMap("Amount", "sfdc:amount", "xsd:decimal"),
                PropMap("StageName", "sfdc:stageName"),
                PropMap("Probability", "sfdc:probability", "xsd:integer"),
                PropMap("CloseDate", "sfdc:closeDate"),
                PropMap("Type", "sfdc:opportunityType"),
                PropMap("ForecastCategory", "sfdc:forecastCategory"),
            ],
            edges=[EdgeMap("AccountId", "sfdc:relatedAccount", "Account")],
        ),
        TableMap(
            table="Case", class_iri="sfdc:Case", uid_prefix="SFDC-CASE", key="Id",
            label=lambda r: r.get("Subject") or f"Case {r.get('CaseNumber')}",
            literals=[
                PropMap("Subject", "schema:name"),
                PropMap("CaseNumber", "sfdc:caseNumber"),
                PropMap("Status", "sfdc:status"),
                PropMap("Priority", "sfdc:priority"),
                PropMap("Type", "sfdc:caseType"),
                PropMap("Origin", "sfdc:origin"),
            ],
            edges=[
                EdgeMap("AccountId", "sfdc:relatedAccount", "Account"),
                EdgeMap("ContactId", "sfdc:relatedContact", "Contact"),
            ],
        ),
        TableMap(
            table="Lead", class_iri="sfdc:Lead", uid_prefix="SFDC-LEAD", key="Id",
            label=lambda r: f"{r.get('FirstName')} {r.get('LastName')} ({r.get('Company')})",
            literals=[
                PropMap("Company", "schema:name"),
                PropMap("FirstName", "sfdc:firstName"),
                PropMap("LastName", "sfdc:lastName"),
                PropMap("Email", "schema:email"),
                PropMap("Status", "sfdc:status"),
                PropMap("Rating", "sfdc:rating"),
                PropMap("Industry", "sfdc:industry"),
                PropMap("LeadSource", "sfdc:leadSource"),
            ],
        ),
        TableMap(
            table="Product2", class_iri="sfdc:Product", uid_prefix="SFDC-PROD", key="Id",
            label="Name",
            literals=[
                PropMap("Name", "schema:name"),
                PropMap("ProductCode", "sfdc:productCode"),
                PropMap("Family", "sfdc:family"),
                PropMap("StockKeepingUnit", "sfdc:sku"),
                PropMap("QuantityUnitOfMeasure", "sfdc:unitOfMeasure"),
            ],
        ),
        TableMap(
            table="Campaign", class_iri="sfdc:Campaign", uid_prefix="SFDC-CMP", key="Id",
            label="Name",
            literals=[
                PropMap("Name", "schema:name"),
                PropMap("Type", "sfdc:campaignType"),
                PropMap("Status", "sfdc:status"),
                PropMap("BudgetedCost", "sfdc:budgetedCost", "xsd:decimal"),
                PropMap("ExpectedRevenue", "sfdc:expectedRevenue", "xsd:decimal"),
            ],
        ),
        TableMap(
            table="Task", class_iri="sfdc:Task", uid_prefix="SFDC-TASK", key="Id",
            label=lambda r: r.get("Subject") or "Task",
            literals=[
                PropMap("Subject", "schema:name"),
                PropMap("Status", "sfdc:status"),
                PropMap("Priority", "sfdc:priority"),
                PropMap("ActivityDate", "sfdc:activityDate"),
            ],
            edges=[
                EdgeMap("WhatId", "sfdc:relatedAccount", "Account"),
                EdgeMap("WhoId", "sfdc:relatedContact", "Contact"),
            ],
        ),
    ],
)
