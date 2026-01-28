# ============================================================================
# SNOWFLAKE DATA CLOUD ARCHITECTURE - Multi-Source System Demo
# ============================================================================
# 
# A comprehensive dashboard demonstrating:
#   1. Source System Explorer - Browse data from SAP, Salesforce, Oracle, 
#      FHIR, Workday, and ServiceNow
#   2. Cortex Analyst - Natural language queries on semantic views
#   3. Horizon Governance - Role-based access control
#   4. Contract Health - Data quality monitoring
#   5. Data Products - Self-service discovery
#
# This app runs in Streamlit in Snowflake (SiS).
# ============================================================================

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

# ============================================================================
# PAGE CONFIGURATION
# ============================================================================

st.set_page_config(
    page_title="Snowflake DCA Demo",
    page_icon="❄️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ============================================================================
# STYLING
# ============================================================================

st.markdown("""
<style>
    .stApp {
        background: linear-gradient(180deg, #FFFFFF 0%, #F0F9FF 100%);
    }
    
    [data-testid="stSidebar"] {
        background: linear-gradient(180deg, #11567F 0%, #0D3D5C 100%);
    }
    
    [data-testid="stSidebar"] * {
        color: white !important;
    }
    
    .main-header {
        background: linear-gradient(135deg, #29B5E8 0%, #11567F 100%);
        padding: 1.5rem 2rem;
        border-radius: 16px;
        margin-bottom: 1.5rem;
        color: white;
        box-shadow: 0 4px 20px rgba(41, 181, 232, 0.3);
    }
    
    .main-header h1 { margin: 0; font-size: 1.75rem; font-weight: 700; }
    .main-header p { margin: 0.5rem 0 0 0; opacity: 0.9; font-size: 0.95rem; }
    
    .metric-card {
        background: white;
        border-radius: 12px;
        padding: 1.25rem;
        border-left: 4px solid #29B5E8;
        box-shadow: 0 2px 8px rgba(0,0,0,0.06);
        margin-bottom: 0.5rem;
    }
    
    .source-card {
        background: white;
        border-radius: 12px;
        padding: 1.25rem;
        border: 1px solid #E2E8F0;
        margin-bottom: 1rem;
        cursor: pointer;
        transition: all 0.2s;
    }
    
    .source-card:hover {
        border-color: #29B5E8;
        box-shadow: 0 4px 12px rgba(41, 181, 232, 0.15);
    }
    
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
</style>
""", unsafe_allow_html=True)

# ============================================================================
# SOURCE SYSTEM CONFIGURATION
# ============================================================================

SOURCE_SYSTEMS = {
    "SAP": {
        "icon": "🏭",
        "color": "#0FAAFF",
        "description": "SAP S/4HANA ERP - Finance, Sales, Procurement, HR",
        "tables": ["KNA1", "LFA1", "MARA", "VBAK", "VBAP", "EKKO", "BKPF", "PA0001", "PA0002"]
    },
    "SALESFORCE": {
        "icon": "☁️",
        "color": "#00A1E0",
        "description": "Salesforce CRM - Accounts, Contacts, Opportunities, Leads",
        "tables": ["ACCOUNT", "CONTACT", "OPPORTUNITY", "LEAD", "CAMPAIGN", "CASE", "TASK", "USER"]
    },
    "ORACLE": {
        "icon": "🔴",
        "color": "#F80000",
        "description": "Oracle EBS - Orders, Payables, Receivables, General Ledger",
        "tables": ["OE_ORDER_HEADERS", "OE_ORDER_LINES", "AP_INVOICES", "AR_INVOICES", 
                   "GL_JE_HEADERS", "GL_JE_LINES", "HZ_PARTIES", "HZ_CUST_ACCOUNTS", "PO_HEADERS"]
    },
    "FHIR": {
        "icon": "🏥",
        "color": "#E8425E",
        "description": "FHIR R4 Healthcare - Patients, Encounters, Observations, Claims",
        "tables": ["PATIENT", "PRACTITIONER", "ENCOUNTER", "OBSERVATION", "CONDITION",
                   "MEDICATION_REQUEST", "CLAIM", "EXPLANATION_OF_BENEFIT", "ORGANIZATION"]
    },
    "WORKDAY": {
        "icon": "👥",
        "color": "#F68D2E",
        "description": "Workday HCM - Workers, Compensation, Time Off, Benefits",
        "tables": ["WORKERS", "POSITIONS", "COMPENSATION", "TIME_OFF_REQUESTS",
                   "BENEFIT_ENROLLMENTS", "ORGANIZATIONS"]
    },
    "SERVICENOW": {
        "icon": "🎫",
        "color": "#81B5A1",
        "description": "ServiceNow ITSM - Incidents, Changes, Problems, CMDB",
        "tables": ["INCIDENT", "CHANGE_REQUEST", "PROBLEM", "SC_REQUEST", "SYS_USER", "CMDB_CI"]
    }
}

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

@st.cache_resource
def get_session():
    """Get Snowflake session"""
    return get_active_session()

def get_current_role() -> str:
    """Get the current active role"""
    session = get_session()
    try:
        result = session.sql("SELECT CURRENT_ROLE() AS ROLE").to_pandas()
        return result['ROLE'].iloc[0] if not result.empty else "Unknown"
    except:
        return "Unknown"

def switch_role(role_name: str) -> bool:
    """Switch to a different role"""
    session = get_session()
    try:
        session.sql(f"USE ROLE {role_name}").collect()
        return True
    except Exception as e:
        st.error(f"Cannot switch to {role_name}: {str(e)}")
        return False

# ============================================================================
# DATA FUNCTIONS
# ============================================================================

@st.cache_data(ttl=60)
def get_source_system_stats():
    """Get statistics for all source systems"""
    session = get_session()
    try:
        df = session.sql("""
            SELECT 
                TABLE_SCHEMA AS SOURCE_SYSTEM,
                COUNT(*) AS TABLE_COUNT,
                SUM(ROW_COUNT) AS TOTAL_ROWS
            FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STAGING', 'SHARED')
              AND TABLE_TYPE = 'BASE TABLE'
              AND TABLE_NAME NOT LIKE '%_TEMPLATE'
            GROUP BY TABLE_SCHEMA
            ORDER BY SOURCE_SYSTEM
        """).to_pandas()
        return df
    except Exception as e:
        st.warning(f"Could not load source stats: {str(e)}")
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_tables_for_source(source_system: str):
    """Get tables for a specific source system"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                TABLE_NAME,
                ROW_COUNT,
                CREATED AS CREATED_AT,
                LAST_ALTERED AS LAST_MODIFIED
            FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = '{source_system}'
              AND TABLE_TYPE = 'BASE TABLE'
              AND TABLE_NAME NOT LIKE '%_TEMPLATE'
            ORDER BY TABLE_NAME
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_curated_stats(source_system: str):
    """Get curated layer stats for a source system"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                TABLE_NAME,
                CASE 
                    WHEN TABLE_NAME LIKE 'DIM_%' THEN 'DIMENSION'
                    WHEN TABLE_NAME LIKE 'FACT_%' THEN 'FACT'
                    ELSE 'OTHER'
                END AS TABLE_TYPE,
                ROW_COUNT
            FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA = '{source_system}'
              AND TABLE_TYPE IN ('BASE TABLE', 'DYNAMIC TABLE')
            ORDER BY TABLE_TYPE, TABLE_NAME
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_semantic_views(source_system: str = None):
    """Get available semantic views (Native Semantic Views)"""
    session = get_session()
    try:
        # Try SEMANTIC_VIEWS first (for Native Semantic Views)
        where_clause = f"WHERE SCHEMA_NAME = '{source_system}'" if source_system else ""
        where_clause += " AND SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')" if not where_clause else " AND SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')"
        
        df = session.sql(f"""
            SELECT 
                SCHEMA_NAME AS SOURCE_SYSTEM,
                SEMANTIC_VIEW_NAME AS VIEW_NAME,
                COMMENT AS DESCRIPTION
            FROM SEM_DEV.INFORMATION_SCHEMA.SEMANTIC_VIEWS
            {where_clause}
            ORDER BY SCHEMA_NAME, SEMANTIC_VIEW_NAME
        """).to_pandas()
        
        if not df.empty:
            return df
            
        # Fallback to regular views if no semantic views found
        where_clause = f"WHERE TABLE_SCHEMA = '{source_system}'" if source_system else ""
        where_clause += " AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')" if not where_clause else " AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')"
        
        df = session.sql(f"""
            SELECT 
                TABLE_SCHEMA AS SOURCE_SYSTEM,
                TABLE_NAME AS VIEW_NAME,
                COMMENT AS DESCRIPTION
            FROM SEM_DEV.INFORMATION_SCHEMA.VIEWS
            {where_clause}
            ORDER BY TABLE_SCHEMA, TABLE_NAME
        """).to_pandas()
        return df
    except Exception as e:
        # If SEMANTIC_VIEWS doesn't exist, try regular views
        try:
            where_clause = f"WHERE TABLE_SCHEMA = '{source_system}'" if source_system else ""
            where_clause += " AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')" if not where_clause else " AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')"
            
            df = session.sql(f"""
                SELECT 
                    TABLE_SCHEMA AS SOURCE_SYSTEM,
                    TABLE_NAME AS VIEW_NAME,
                    COMMENT AS DESCRIPTION
                FROM SEM_DEV.INFORMATION_SCHEMA.VIEWS
                {where_clause}
                ORDER BY TABLE_SCHEMA, TABLE_NAME
            """).to_pandas()
            return df
        except:
            return pd.DataFrame()

def sample_table_data(source_system: str, table_name: str, limit: int = 100):
    """Sample data from a table"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT * 
            FROM RAW_DEV.{source_system}.{table_name}
            LIMIT {limit}
        """).to_pandas()
        return df
    except Exception as e:
        return None, str(e)

@st.cache_data(ttl=60)
def get_contract_health():
    """Get contract health summary"""
    session = get_session()
    try:
        df = session.sql("""
            SELECT 
                SOURCE_SYSTEM,
                COUNT(*) AS TOTAL_CONTRACTS,
                SUM(CASE WHEN LAST_PASSED THEN 1 ELSE 0 END) AS HEALTHY,
                SUM(CASE WHEN NOT LAST_PASSED OR LAST_PASSED IS NULL THEN 1 ELSE 0 END) AS ISSUES
            FROM GOVERNANCE.CONTRACTS.VW_CONTRACT_HEALTH
            GROUP BY SOURCE_SYSTEM
            ORDER BY SOURCE_SYSTEM
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

@st.cache_data(ttl=30)
def get_contract_details(source_system: str = None):
    """Get detailed contract information for drill-down"""
    session = get_session()
    try:
        where_clause = f"WHERE SOURCE_SYSTEM = '{source_system}'" if source_system else ""
        df = session.sql(f"""
            SELECT 
                CONTRACT_ID,
                CONTRACT_NAME,
                SOURCE_SYSTEM,
                SOURCE_TABLE,
                HEALTH_STATUS,
                LAST_VALIDATION,
                LAST_PASSED,
                SCHEMA_PASSED,
                QUALITY_PASSED,
                SLA_PASSED,
                TOTAL_ROWS
            FROM GOVERNANCE.CONTRACTS.VW_CONTRACT_HEALTH
            {where_clause}
            ORDER BY 
                CASE HEALTH_STATUS 
                    WHEN 'CRITICAL' THEN 1 
                    WHEN 'QUALITY_ISSUES' THEN 2
                    WHEN 'SLA_DEGRADED' THEN 3
                    WHEN 'NOT_VALIDATED' THEN 4
                    WHEN 'HEALTHY' THEN 5
                END,
                SOURCE_SYSTEM, SOURCE_TABLE
        """).to_pandas()
        return df
    except Exception as e:
        st.warning(f"Could not load contract details: {str(e)}")
        return pd.DataFrame()

@st.cache_data(ttl=30)
def get_validation_history(contract_id: str):
    """Get validation history for a specific contract"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                VALIDATION_ID,
                VALIDATION_START,
                VALIDATION_END,
                SCHEMA_PASSED,
                QUALITY_PASSED,
                SLA_PASSED,
                OVERALL_PASSED,
                TOTAL_ROWS,
                VALIDATION_DETAILS
            FROM GOVERNANCE.CONTRACTS.VALIDATION_HISTORY
            WHERE CONTRACT_ID = '{contract_id}'
            ORDER BY VALIDATION_START DESC
            LIMIT 20
        """).to_pandas()
        return df
    except Exception as e:
        return pd.DataFrame()

@st.cache_data(ttl=30)
def get_contract_registry_detail(contract_id: str):
    """Get full contract details from registry"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                CONTRACT_ID,
                CONTRACT_NAME,
                CONTRACT_VERSION,
                SOURCE_SYSTEM,
                SOURCE_TABLE,
                FULL_TABLE_PATH,
                PRODUCER_TEAM,
                CONSUMER_TEAMS,
                EFFECTIVE_FROM,
                EFFECTIVE_TO,
                IS_ACTIVE,
                SCHEMA_DEFINITION,
                QUALITY_DEFINITION,
                SLA_DEFINITION,
                GOVERNANCE_DEFINITION
            FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY
            WHERE CONTRACT_ID = '{contract_id}'
        """).to_pandas()
        return df
    except Exception as e:
        return pd.DataFrame()

@st.cache_data(ttl=30)
def get_sla_definition(contract_id: str):
    """Get SLA definition for a contract"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                FRESHNESS_TARGET_HOURS,
                FRESHNESS_MAX_HOURS,
                AVAILABILITY_TARGET_PCT,
                MIN_ROW_COUNT,
                MAX_ROW_COUNT
            FROM GOVERNANCE.CONTRACTS.SLA_DEFINITIONS
            WHERE CONTRACT_ID = '{contract_id}'
        """).to_pandas()
        return df
    except Exception as e:
        return pd.DataFrame()

def validate_contract(contract_id: str):
    """Run validation for a specific contract"""
    session = get_session()
    try:
        result = session.sql(f"CALL GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT('{contract_id}')").collect()
        return result[0][0] if result else None
    except Exception as e:
        return f"Error: {str(e)}"

# ============================================================================
# ROLE DEFINITIONS
# ============================================================================

AVAILABLE_ROLES = [
    ("DATA_ADMIN", "🔧 Data Admin", "Full system access"),
    ("DATA_STEWARD", "📋 Data Steward", "Governance access"),
    ("DATA_ENGINEER", "⚙️ Data Engineer", "Pipeline access"),
    ("ANALYST", "📊 Analyst", "Analytics access"),
    ("MANAGER", "👔 Manager", "Department access"),
    ("VIEWER", "👁️ Viewer", "Read-only access"),
]

# ============================================================================
# SIDEBAR
# ============================================================================

def render_sidebar():
    """Render sidebar navigation"""
    with st.sidebar:
        st.markdown("""
        <div style="text-align: center; padding: 1rem 0 1.5rem 0;">
            <div style="font-size: 3rem; margin-bottom: 0.5rem;">❄️</div>
            <h2 style="color: white; font-size: 1.2rem; margin: 0;">Snowflake DCA</h2>
            <p style="color: #29B5E8; font-size: 0.85rem;">Multi-Source Demo</p>
        </div>
        """, unsafe_allow_html=True)
        
        st.divider()
        
        # Role Switcher
        st.markdown("### 🔐 Role")
        current_role = get_current_role()
        
        role_options = [f"{r[1]}" for r in AVAILABLE_ROLES]
        role_names = [r[0] for r in AVAILABLE_ROLES]
        
        try:
            current_idx = role_names.index(current_role)
        except ValueError:
            current_idx = 0
        
        selected_display = st.selectbox(
            "Select Role",
            role_options,
            index=current_idx,
            label_visibility="collapsed"
        )
        
        selected_idx = role_options.index(selected_display)
        selected_role = role_names[selected_idx]
        
        if selected_role != current_role:
            if st.button("🔄 Switch Role", use_container_width=True):
                if switch_role(selected_role):
                    st.success(f"Switched to {selected_role}")
                    st.cache_data.clear()
                    st.experimental_rerun()
        
        st.divider()
        
        # Navigation
        page = st.radio(
            "Navigation",
            ["🏠 Dashboard", "🔍 Source Explorer", "🤖 Cortex Analyst", 
             "🔮 Governance", "📋 Contracts", "ℹ️ About"],
            label_visibility="collapsed"
        )
        
        st.divider()
        
        # Source system stats
        st.markdown("### 📊 Source Systems")
        stats = get_source_system_stats()
        if not stats.empty:
            for _, row in stats.iterrows():
                source = row['SOURCE_SYSTEM']
                if source in SOURCE_SYSTEMS:
                    icon = SOURCE_SYSTEMS[source]['icon']
                    st.markdown(f"{icon} **{source}**: {int(row['TABLE_COUNT'])} tables")
        
        return page

# ============================================================================
# PAGE: DASHBOARD
# ============================================================================

def render_dashboard():
    """Render main dashboard"""
    st.markdown("""
    <div class="main-header">
        <h1>🏠 Enterprise Data Dashboard</h1>
        <p>Multi-source system data integration powered by Snowflake</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Source System Overview
    st.markdown("### 📊 Source System Overview")
    
    stats = get_source_system_stats()
    
    if not stats.empty:
        cols = st.columns(len(SOURCE_SYSTEMS))
        for i, (source, config) in enumerate(SOURCE_SYSTEMS.items()):
            with cols[i]:
                source_stats = stats[stats['SOURCE_SYSTEM'] == source]
                table_count = int(source_stats['TABLE_COUNT'].iloc[0]) if not source_stats.empty else 0
                row_count = int(source_stats['TOTAL_ROWS'].iloc[0]) if not source_stats.empty and source_stats['TOTAL_ROWS'].iloc[0] else 0
                
                st.markdown(f"""
                <div class="metric-card" style="border-left-color: {config['color']};">
                    <div style="font-size: 1.5rem;">{config['icon']}</div>
                    <strong>{source}</strong>
                    <div style="font-size: 1.5rem; font-weight: 700;">{table_count}</div>
                    <small style="color: #64748B;">tables • {row_count:,} rows</small>
                </div>
                """, unsafe_allow_html=True)
    else:
        st.info("No source system data available. Run the data load scripts first.")
    
    st.divider()
    
    # Architecture Overview
    col1, col2 = st.columns(2)
    
    with col1:
        st.markdown("### 🏗️ Data Architecture")
        st.markdown("""
        | Layer | Database | Purpose |
        |-------|----------|---------|
        | **RAW** | RAW_DEV | Ingested data with SCD Type 2 |
        | **CURATED** | CURATED_DEV | Dynamic Tables (star schema) |
        | **SEMANTIC** | SEM_DEV | Native Semantic Views |
        | **GOVERNANCE** | GOVERNANCE | Policies & Contracts |
        """)
    
    with col2:
        st.markdown("### 🔒 Governance Features")
        st.markdown("""
        - **Dynamic Masking** — Role-based PII protection
        - **Row Access Policies** — Context-aware filtering  
        - **Object Tags** — Classification & compliance
        - **Data Contracts** — Quality & SLA enforcement
        - **Audit Logging** — Complete access history
        """)

# ============================================================================
# PAGE: SOURCE EXPLORER
# ============================================================================

def render_source_explorer():
    """Render source system explorer"""
    st.markdown("""
    <div class="main-header">
        <h1>🔍 Source System Explorer</h1>
        <p>Browse data from all integrated enterprise systems</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Source system selector
    col1, col2 = st.columns([1, 3])
    
    with col1:
        st.markdown("### Select Source")
        selected_source = st.radio(
            "Source System",
            list(SOURCE_SYSTEMS.keys()),
            format_func=lambda x: f"{SOURCE_SYSTEMS[x]['icon']} {x}",
            label_visibility="collapsed"
        )
    
    with col2:
        config = SOURCE_SYSTEMS[selected_source]
        
        st.markdown(f"""
        ### {config['icon']} {selected_source}
        {config['description']}
        """)
        
        # Get tables
        tables_df = get_tables_for_source(selected_source)
        
        if not tables_df.empty:
            tab1, tab2, tab3 = st.tabs(["📋 RAW Tables", "⚙️ Curated Layer", "📊 Sample Data"])
            
            with tab1:
                st.dataframe(tables_df, use_container_width=True)
            
            with tab2:
                curated_df = get_curated_stats(selected_source)
                if not curated_df.empty:
                    st.dataframe(curated_df, use_container_width=True)
                else:
                    st.info("No curated tables found. Run BUILD_CURATED_LAYER() first.")
            
            with tab3:
                table_options = tables_df['TABLE_NAME'].tolist()
                selected_table = st.selectbox("Select Table", table_options)
                
                if st.button("🔍 Load Sample Data"):
                    with st.spinner("Loading..."):
                        sample_df = sample_table_data(selected_source, selected_table, 50)
                        if sample_df is not None and not sample_df.empty:
                            st.dataframe(sample_df, use_container_width=True)
                        else:
                            st.error("Could not load sample data")
        else:
            st.warning(f"No tables found for {selected_source}. Load data first.")

# ============================================================================
# PAGE: CORTEX ANALYST
# ============================================================================

def render_cortex_page():
    """Render Cortex Analyst interface"""
    st.markdown("""
    <div class="main-header">
        <h1>🤖 Cortex Analyst</h1>
        <p>Natural language queries powered by Snowflake Cortex</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Get semantic views
    sem_views = get_semantic_views()
    
    if not sem_views.empty:
        col1, col2 = st.columns([2, 1])
        
        with col1:
            # Create view selector
            view_options = sem_views.apply(
                lambda x: f"{x['SOURCE_SYSTEM']}.{x['VIEW_NAME']}", axis=1
            ).tolist()
            
            selected_view = st.selectbox("Select Semantic View", view_options)
        
        with col2:
            if st.button("🔄 Clear Chat"):
                st.session_state.cortex_history = []
                st.experimental_rerun()
        
        # Initialize chat
        if "cortex_history" not in st.session_state:
            st.session_state.cortex_history = []
        
        # Sample questions based on source
        source = selected_view.split('.')[0] if selected_view else ""
        
        sample_questions = {
            "SAP": ["Total sales orders by region", "Top vendors by purchase volume", "Customer count by country"],
            "SALESFORCE": ["Opportunities by stage", "Lead conversion rate", "Accounts by industry"],
            "ORACLE": ["Open invoices by vendor", "Revenue by period", "Order backlog"],
            "FHIR": ["Patients by condition", "Encounters by type", "Claims by status"],
            "WORKDAY": ["Headcount by department", "Compensation by level", "Time off requests"],
            "SERVICENOW": ["Incidents by priority", "Change requests by status", "MTTR by category"]
        }
        
        st.markdown("#### 💡 Sample Questions")
        questions = sample_questions.get(source, ["Show me summary statistics"])
        cols = st.columns(len(questions))
        for i, q in enumerate(questions):
            with cols[i]:
                if st.button(f"💬 {q}", key=f"q_{i}", use_container_width=True):
                    st.session_state.pending_question = q
                    st.experimental_rerun()
        
        st.divider()
        
        # Chat input
        question = st.text_input("Ask a question about your data", placeholder="Type your question here...")
        
        if st.button("🚀 Ask Cortex", use_container_width=False):
            if question:
                st.info(f"Processing: {question}")
                st.info(f"Using semantic view: SEM_DEV.{selected_view}")
                st.warning("Note: Full Cortex Analyst integration requires semantic model YAML configuration.")
    else:
        st.warning("No semantic views found. Run BUILD_SEMANTIC_LAYER() first.")

# ============================================================================
# PAGE: GOVERNANCE
# ============================================================================

def render_governance_page():
    """Render governance demonstration"""
    st.markdown("""
    <div class="main-header">
        <h1>🔮 Horizon Governance</h1>
        <p>Role-based access control and data protection</p>
    </div>
    """, unsafe_allow_html=True)
    
    current_role = get_current_role()
    
    st.info(f"**Current Role:** {current_role} — Switch roles in the sidebar to see different access levels")
    
    st.markdown("### 📋 Access Matrix")
    
    st.markdown("""
    | Role | RAW Layer | Curated Layer | Semantic Layer | PII Access | Governance |
    |------|-----------|---------------|----------------|------------|------------|
    | 🔧 DATA_ADMIN | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
    | 📋 DATA_STEWARD | ✅ Read | ✅ Full | ✅ Full | 🔒 Masked | ✅ Full |
    | ⚙️ DATA_ENGINEER | ✅ Full | ✅ Full | ✅ Read | 🔒 Masked | ❌ None |
    | 📊 ANALYST | ❌ None | ✅ Read | ✅ Full | 🔒 Masked | ❌ None |
    | 👔 MANAGER | ❌ None | ✅ Read | ✅ Read | 🔓 Partial | ❌ None |
    | 👁️ VIEWER | ❌ None | ❌ None | ✅ Read | ❌ None | ❌ None |
    """)
    
    st.divider()
    
    st.markdown("### 🏷️ Classification Tags")
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.markdown("""
        **Data Classification**
        - `PUBLIC` - Open data
        - `INTERNAL` - Internal use
        - `CONFIDENTIAL` - Sensitive
        - `RESTRICTED` - Highly sensitive
        """)
    
    with col2:
        st.markdown("""
        **PII Types**
        - `NAME` - Personal names
        - `EMAIL` - Email addresses
        - `PHONE` - Phone numbers
        - `SSN` - Social Security
        - `DOB` - Date of birth
        """)
    
    with col3:
        st.markdown("""
        **Compliance**
        - `GDPR` - EU data protection
        - `HIPAA` - Healthcare
        - `CCPA` - California privacy
        - `SOX` - Financial controls
        """)

# ============================================================================
# PAGE: CONTRACTS
# ============================================================================

def render_contracts_page():
    """Render contracts dashboard with drill-to-detail"""
    st.markdown("""
    <div class="main-header">
        <h1>📋 Data Contracts</h1>
        <p>Quality, schema, and SLA enforcement</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Initialize session state for drill-down
    if "selected_contract" not in st.session_state:
        st.session_state.selected_contract = None
    if "selected_source_filter" not in st.session_state:
        st.session_state.selected_source_filter = None
    
    health = get_contract_health()
    
    if not health.empty:
        st.markdown("### Contract Health by Source System")
        st.caption("Click a source system card to filter contracts")
        
        cols = st.columns(len(health))
        for i, row in health.iterrows():
            with cols[i]:
                source = row['SOURCE_SYSTEM']
                config = SOURCE_SYSTEMS.get(source, {"icon": "📦", "color": "#64748B"})
                
                total = row['TOTAL_CONTRACTS']
                healthy = row['HEALTHY']
                pct = (healthy / total * 100) if total > 0 else 0
                
                color = "#18794E" if pct >= 90 else "#AD5700" if pct >= 70 else "#CD2B31"
                
                # Highlight if selected
                border_width = "4px" if st.session_state.selected_source_filter == source else "4px"
                opacity = "1" if st.session_state.selected_source_filter in [None, source] else "0.5"
                
                st.markdown(f"""
                <div class="metric-card" style="border-left-color: {color}; border-left-width: {border_width}; opacity: {opacity};">
                    <div style="font-size: 1.5rem;">{config['icon']}</div>
                    <strong>{source}</strong>
                    <div style="font-size: 1.5rem; font-weight: 700; color: {color};">{pct:.0f}%</div>
                    <small>{healthy}/{total} contracts healthy</small>
                </div>
                """, unsafe_allow_html=True)
                
                if st.button(f"View {source}", key=f"filter_{source}", use_container_width=True):
                    if st.session_state.selected_source_filter == source:
                        st.session_state.selected_source_filter = None
                    else:
                        st.session_state.selected_source_filter = source
                    st.session_state.selected_contract = None
                    st.experimental_rerun()
    else:
        st.info("No contracts found. Generate contracts using GENERATE_CONTRACTS_FOR_SOURCE().")
        return
    
    st.divider()
    
    # Contract Details Section
    col_list, col_detail = st.columns([1, 2])
    
    with col_list:
        st.markdown("### 📋 Contract List")
        
        # Clear filter button
        if st.session_state.selected_source_filter:
            if st.button(f"🔄 Clear Filter ({st.session_state.selected_source_filter})", use_container_width=True):
                st.session_state.selected_source_filter = None
                st.session_state.selected_contract = None
                st.experimental_rerun()
        
        # Get contracts with optional filter
        contracts = get_contract_details(st.session_state.selected_source_filter)
        
        if not contracts.empty:
            for _, contract in contracts.iterrows():
                contract_id = contract['CONTRACT_ID']
                status = contract['HEALTH_STATUS']
                source = contract['SOURCE_SYSTEM']
                table = contract['SOURCE_TABLE']
                
                # Status icons and colors
                status_config = {
                    'HEALTHY': ('✅', '#18794E'),
                    'SLA_DEGRADED': ('⚠️', '#AD5700'),
                    'QUALITY_ISSUES': ('🔶', '#E65100'),
                    'CRITICAL': ('❌', '#CD2B31'),
                    'NOT_VALIDATED': ('⏳', '#64748B')
                }
                icon, color = status_config.get(status, ('❓', '#64748B'))
                
                # Highlight selected
                bg_color = "#1E293B" if st.session_state.selected_contract == contract_id else "transparent"
                
                st.markdown(f"""
                <div style="padding: 0.5rem; margin: 0.25rem 0; border-radius: 4px; 
                            border-left: 3px solid {color}; background: {bg_color};">
                    <span style="font-size: 0.9rem;">{icon} <strong>{table}</strong></span><br/>
                    <small style="color: #94A3B8;">{source} • {status}</small>
                </div>
                """, unsafe_allow_html=True)
                
                if st.button(f"Details", key=f"detail_{contract_id}", use_container_width=True):
                    st.session_state.selected_contract = contract_id
                    st.experimental_rerun()
        else:
            st.info("No contracts found for filter.")
    
    with col_detail:
        if st.session_state.selected_contract:
            render_contract_detail(st.session_state.selected_contract)
        else:
            st.markdown("### 📝 Contract Components")
            st.info("Select a contract from the list to view details")
            
            col1, col2 = st.columns(2)
            
            with col1:
                st.markdown("""
                **Schema Contract**
                - Column names and types
                - Required vs optional fields
                - Data format specifications
                
                **Quality Contract**
                - Null rate thresholds
                - Uniqueness constraints
                - Referential integrity
                """)
            
            with col2:
                st.markdown("""
                **SLA Contract**
                - Freshness requirements
                - Availability targets
                - Row count minimums
                
                **Governance Contract**
                - Classification level
                - PII requirements
                - Retention policies
                """)

def render_contract_detail(contract_id: str):
    """Render detailed view for a specific contract"""
    st.markdown("### 🔍 Contract Details")
    
    # Get contract registry info
    registry = get_contract_registry_detail(contract_id)
    
    if registry.empty:
        st.warning(f"Contract not found: {contract_id}")
        return
    
    contract = registry.iloc[0]
    
    # Header with status
    contracts_df = get_contract_details()
    contract_health = contracts_df[contracts_df['CONTRACT_ID'] == contract_id]
    
    if not contract_health.empty:
        health = contract_health.iloc[0]
        status = health['HEALTH_STATUS']
        
        status_config = {
            'HEALTHY': ('✅', '#18794E', 'All checks passing'),
            'SLA_DEGRADED': ('⚠️', '#AD5700', 'SLA target missed'),
            'QUALITY_ISSUES': ('🔶', '#E65100', 'Quality checks failing'),
            'CRITICAL': ('❌', '#CD2B31', 'Critical issues detected'),
            'NOT_VALIDATED': ('⏳', '#64748B', 'Awaiting validation')
        }
        icon, color, desc = status_config.get(status, ('❓', '#64748B', 'Unknown'))
        
        st.markdown(f"""
        <div style="padding: 1rem; background: linear-gradient(135deg, {color}22, {color}11); 
                    border-radius: 8px; border-left: 4px solid {color}; margin-bottom: 1rem;">
            <h3 style="margin: 0;">{icon} {contract['CONTRACT_NAME']}</h3>
            <p style="margin: 0.5rem 0 0 0; color: #94A3B8;">
                {contract['SOURCE_SYSTEM']} • {contract['SOURCE_TABLE']} • {desc}
            </p>
        </div>
        """, unsafe_allow_html=True)
        
        # Validation status cards
        st.markdown("#### Validation Status")
        cols = st.columns(4)
        
        with cols[0]:
            schema_icon = "✅" if health['SCHEMA_PASSED'] else "❌" if health['SCHEMA_PASSED'] is False else "⏳"
            st.metric("Schema", schema_icon)
        with cols[1]:
            quality_icon = "✅" if health['QUALITY_PASSED'] else "❌" if health['QUALITY_PASSED'] is False else "⏳"
            st.metric("Quality", quality_icon)
        with cols[2]:
            sla_icon = "✅" if health['SLA_PASSED'] else "❌" if health['SLA_PASSED'] is False else "⏳"
            st.metric("SLA", sla_icon)
        with cols[3]:
            overall_icon = "✅" if health['LAST_PASSED'] else "❌" if health['LAST_PASSED'] is False else "⏳"
            st.metric("Overall", overall_icon)
    
    # Tabs for different aspects
    tab1, tab2, tab3, tab4 = st.tabs(["📊 SLA", "🔄 History", "📋 Schema", "⚙️ Actions"])
    
    with tab1:
        st.markdown("##### SLA Definition")
        sla = get_sla_definition(contract_id)
        
        if not sla.empty:
            sla_def = sla.iloc[0]
            col1, col2 = st.columns(2)
            
            with col1:
                st.metric("Freshness Target", f"{sla_def['FRESHNESS_TARGET_HOURS']}h")
                st.metric("Freshness Max", f"{sla_def['FRESHNESS_MAX_HOURS']}h")
            with col2:
                st.metric("Availability Target", f"{sla_def['AVAILABILITY_TARGET_PCT']}%")
                min_rows = sla_def['MIN_ROW_COUNT']
                max_rows = sla_def['MAX_ROW_COUNT']
                st.metric("Row Count Range", f"{min_rows:,} - {max_rows:,}" if max_rows else f"{min_rows:,}+")
        else:
            st.info("No SLA definition found for this contract.")
    
    with tab2:
        st.markdown("##### Validation History")
        history = get_validation_history(contract_id)
        
        if not history.empty:
            for _, val in history.iterrows():
                passed = val['OVERALL_PASSED']
                icon = "✅" if passed else "❌"
                timestamp = val['VALIDATION_START']
                rows = val['TOTAL_ROWS']
                
                st.markdown(f"""
                <div style="padding: 0.5rem; margin: 0.25rem 0; border-radius: 4px; 
                            border-left: 3px solid {'#18794E' if passed else '#CD2B31'}; 
                            background: {'#18794E11' if passed else '#CD2B3111'};">
                    <span>{icon} <strong>{timestamp}</strong></span><br/>
                    <small>Schema: {'✓' if val['SCHEMA_PASSED'] else '✗'} | 
                           Quality: {'✓' if val['QUALITY_PASSED'] else '✗'} | 
                           SLA: {'✓' if val['SLA_PASSED'] else '✗'} | 
                           Rows: {rows:,}</small>
                </div>
                """, unsafe_allow_html=True)
        else:
            st.info("No validation history found. Run validation to see results.")
    
    with tab3:
        st.markdown("##### Contract Metadata")
        
        st.markdown(f"""
        | Property | Value |
        |----------|-------|
        | **Contract ID** | `{contract['CONTRACT_ID']}` |
        | **Version** | {contract['CONTRACT_VERSION']} |
        | **Table Path** | `{contract['FULL_TABLE_PATH']}` |
        | **Producer** | {contract['PRODUCER_TEAM']} |
        | **Effective From** | {contract['EFFECTIVE_FROM']} |
        | **Active** | {'Yes' if contract['IS_ACTIVE'] else 'No'} |
        """)
    
    with tab4:
        st.markdown("##### Contract Actions")
        
        col1, col2 = st.columns(2)
        
        with col1:
            if st.button("🔄 Run Validation", use_container_width=True):
                with st.spinner("Validating contract..."):
                    result = validate_contract(contract_id)
                    if result and not str(result).startswith("Error"):
                        st.success("Validation complete!")
                        st.json(result)
                        # Clear cache to refresh data
                        get_contract_details.clear()
                        get_validation_history.clear()
                    else:
                        st.error(f"Validation failed: {result}")
        
        with col2:
            if st.button("📋 Copy Contract ID", use_container_width=True):
                st.code(contract_id)
        
        st.divider()
        
        if st.button("← Back to List", use_container_width=True):
            st.session_state.selected_contract = None
            st.experimental_rerun()

# ============================================================================
# PAGE: ABOUT
# ============================================================================

def render_about_page():
    """Render about page"""
    st.markdown("""
    <div class="main-header">
        <h1>ℹ️ About This Demo</h1>
        <p>Snowflake Data Cloud Architecture - Multi-Source Full Stack Demo</p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown("""
    ### 🎯 What This Demo Shows
    
    This demo showcases a complete enterprise data platform integrating data from 
    **6 major enterprise systems**:
    
    | System | Domain | Key Tables |
    |--------|--------|------------|
    | 🏭 SAP S/4HANA | ERP | Customers, Vendors, Materials, Sales, Purchasing |
    | ☁️ Salesforce | CRM | Accounts, Contacts, Opportunities, Leads |
    | 🔴 Oracle EBS | Finance | Orders, AP, AR, General Ledger |
    | 🏥 FHIR R4 | Healthcare | Patients, Encounters, Claims |
    | 👥 Workday | HCM | Workers, Compensation, Benefits |
    | 🎫 ServiceNow | ITSM | Incidents, Changes, Problems |
    
    ### 🏗️ Architecture Layers
    
    - **RAW Layer** — SCD Type 2 history, schema inference, dynamic tables
    - **CURATED Layer** — Star schema with Dynamic Tables, metadata-driven
    - **SEMANTIC Layer** — Native Semantic Views for Cortex Analyst
    - **GOVERNANCE** — Dynamic masking, row access, contracts
    - **MARKETPLACE** — Data products for self-service
    
    ### 🔧 Key Features Demonstrated
    
    - Dynamic Tables with automatic refresh
    - Native Semantic Views
    - Snowflake Horizon governance
    - Role-based access control
    - Data contracts and quality
    - Cortex AI integration
    """)

# ============================================================================
# MAIN
# ============================================================================

def main():
    """Main application entry point"""
    page = render_sidebar()
    
    if page == "🏠 Dashboard":
        render_dashboard()
    elif page == "🔍 Source Explorer":
        render_source_explorer()
    elif page == "🤖 Cortex Analyst":
        render_cortex_page()
    elif page == "🔮 Governance":
        render_governance_page()
    elif page == "📋 Contracts":
        render_contracts_page()
    elif page == "ℹ️ About":
        render_about_page()

if __name__ == "__main__":
    main()
