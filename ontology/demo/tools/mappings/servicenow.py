"""ServiceNow ITSM/CMDB -> ontology mapping (curated).

Tables (from the main generator's ServiceNowGenerator):
  sys_user        -> snow:User
  incident        -> snow:Incident      (caller_id/assigned_to -> User)
  change_request  -> snow:ChangeRequest (assigned_to/requested_by -> User)
  problem         -> snow:Problem       (assigned_to -> User)
  cmdb_ci         -> snow:ConfigurationItem
  sc_request      -> snow:CatalogRequest (requested_for -> User)
  kb_knowledge    -> snow:KnowledgeArticle (author -> User)
"""
from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap

SPEC = MappingSpec(
    system="servicenow",
    namespace_prefix="snow",
    tables=[
        TableMap(
            table="sys_user", class_iri="snow:User", uid_prefix="SNOW-USR", key="sys_id",
            label="name",
            literals=[
                PropMap("name", "schema:name"),
                PropMap("user_name", "snow:userName"),
                PropMap("email", "schema:email"),
                PropMap("title", "snow:title"),
                PropMap("active", "snow:active", "xsd:boolean"),
                PropMap("vip", "snow:vip", "xsd:boolean"),
            ],
        ),
        TableMap(
            table="incident", class_iri="snow:Incident", uid_prefix="SNOW-INC", key="sys_id",
            label=lambda r: r.get("short_description") or r.get("number"),
            literals=[
                PropMap("short_description", "schema:name"),
                PropMap("number", "snow:number"),
                PropMap("state_display", "snow:state"),
                PropMap("priority", "snow:priority", "xsd:integer"),
                PropMap("impact", "snow:impact", "xsd:integer"),
                PropMap("urgency", "snow:urgency", "xsd:integer"),
                PropMap("category", "snow:category"),
                PropMap("opened_at", "snow:openedAt"),
            ],
            edges=[
                EdgeMap("caller_id", "snow:caller", "sys_user"),
                EdgeMap("assigned_to", "snow:assignedTo", "sys_user"),
            ],
        ),
        TableMap(
            table="change_request", class_iri="snow:ChangeRequest", uid_prefix="SNOW-CHG", key="sys_id",
            label=lambda r: r.get("short_description") or r.get("number"),
            literals=[
                PropMap("short_description", "schema:name"),
                PropMap("number", "snow:number"),
                PropMap("state_display", "snow:state"),
                PropMap("type", "snow:changeType"),
                PropMap("risk", "snow:risk"),
                PropMap("start_date", "snow:startDate"),
            ],
            edges=[
                EdgeMap("assigned_to", "snow:assignedTo", "sys_user"),
                EdgeMap("requested_by", "snow:requestedBy", "sys_user"),
            ],
        ),
        TableMap(
            table="problem", class_iri="snow:Problem", uid_prefix="SNOW-PRB", key="sys_id",
            label=lambda r: r.get("short_description") or r.get("number"),
            literals=[
                PropMap("short_description", "schema:name"),
                PropMap("number", "snow:number"),
                PropMap("state_display", "snow:state"),
                PropMap("priority", "snow:priority", "xsd:integer"),
                PropMap("known_error", "snow:knownError", "xsd:boolean"),
            ],
            edges=[EdgeMap("assigned_to", "snow:assignedTo", "sys_user")],
        ),
        TableMap(
            table="cmdb_ci", class_iri="snow:ConfigurationItem", uid_prefix="SNOW-CI", key="sys_id",
            label="name",
            literals=[
                PropMap("name", "schema:name"),
                PropMap("sys_class_name", "snow:ciClass"),
                PropMap("asset_tag", "snow:assetTag"),
                PropMap("serial_number", "snow:serialNumber"),
                PropMap("ip_address", "snow:ipAddress"),
                PropMap("install_status", "snow:installStatus", "xsd:integer"),
                PropMap("cost", "snow:cost", "xsd:decimal"),
            ],
        ),
        TableMap(
            table="sc_request", class_iri="snow:CatalogRequest", uid_prefix="SNOW-REQ", key="sys_id",
            label=lambda r: r.get("short_description") or r.get("number"),
            literals=[
                PropMap("short_description", "schema:name"),
                PropMap("number", "snow:number"),
                PropMap("request_state", "snow:state"),
                PropMap("stage", "snow:stage"),
                PropMap("price", "snow:price", "xsd:decimal"),
            ],
            edges=[EdgeMap("requested_for", "snow:requestedFor", "sys_user")],
        ),
        TableMap(
            table="kb_knowledge", class_iri="snow:KnowledgeArticle", uid_prefix="SNOW-KB", key="sys_id",
            label="short_description",
            literals=[
                PropMap("short_description", "schema:name"),
                PropMap("number", "snow:number"),
                PropMap("workflow_state", "snow:workflowState"),
                PropMap("view_count", "snow:viewCount", "xsd:integer"),
                PropMap("rating", "snow:rating", "xsd:decimal"),
            ],
            edges=[EdgeMap("author", "snow:author", "sys_user")],
        ),
    ],
)
