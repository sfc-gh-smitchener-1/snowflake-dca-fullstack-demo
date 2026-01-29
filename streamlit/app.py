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
    """Get current role (uses demo role from session state if set, otherwise actual role)"""
    # Check for demo/simulated role first
    if "demo_role" in st.session_state:
        return st.session_state.demo_role
    
    # Fall back to actual Snowflake role
    session = get_session()
    try:
        result = session.sql("SELECT CURRENT_ROLE() AS ROLE").to_pandas()
        return result['ROLE'].iloc[0] if not result.empty else "DATA_ADMIN"
    except:
        return "DATA_ADMIN"

def switch_role(role_name: str) -> bool:
    """
    Simulate role switching for demo purposes.
    Note: USE ROLE is not supported in Streamlit in Snowflake.
    In production, users would log in with their assigned role.
    """
    # Store the simulated role in session state for demo purposes
    st.session_state.demo_role = role_name
    return True

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
    
    # Method 1: Try SHOW SEMANTIC VIEWS (most reliable for native semantic views)
    try:
        df = session.sql("SHOW SEMANTIC VIEWS IN DATABASE SEM_DEV").to_pandas()
        if not df.empty:
            # SHOW command returns columns like: name, schema_name, database_name, etc.
            result = df[['schema_name', 'name']].copy()
            result.columns = ['SOURCE_SYSTEM', 'VIEW_NAME']
            result['DESCRIPTION'] = ''
            
            # Filter out system schemas
            result = result[~result['SOURCE_SYSTEM'].isin(['INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG'])]
            
            # Apply source system filter if provided
            if source_system:
                result = result[result['SOURCE_SYSTEM'] == source_system]
            
            return result.sort_values(['SOURCE_SYSTEM', 'VIEW_NAME']).reset_index(drop=True)
    except:
        pass
    
    # Method 2: Try querying the semantic config table directly
    try:
        where_clause = f"WHERE SOURCE_SYSTEM = '{source_system}' AND IS_ACTIVE = TRUE" if source_system else "WHERE IS_ACTIVE = TRUE"
        df = session.sql(f"""
            SELECT DISTINCT
                SOURCE_SYSTEM,
                VIEW_NAME,
                COALESCE(VIEW_COMMENT, '') AS DESCRIPTION
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG
            {where_clause}
            ORDER BY SOURCE_SYSTEM, VIEW_NAME
        """).to_pandas()
        if not df.empty:
            return df
    except:
        pass
    
    # Method 3: Fallback to regular views in INFORMATION_SCHEMA
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
                    st.success(f"Demo: Viewing as {selected_role}")
                    st.experimental_rerun()
        else:
            st.caption(f"✓ Current: {current_role}")
        
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

def get_semantic_views_for_source(source_system: str):
    """Get semantic views for a specific source system"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT 
                VIEW_NAME,
                VIEW_TYPE,
                COALESCE(VIEW_COMMENT, '') AS DESCRIPTION
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG
            WHERE SOURCE_SYSTEM = '{source_system}'
              AND IS_ACTIVE = TRUE
            ORDER BY VIEW_NAME
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

def sample_curated_data(source_system: str, table_name: str, limit: int = 50):
    """Sample data from a curated table"""
    session = get_session()
    try:
        df = session.sql(f"""
            SELECT * 
            FROM CURATED_DEV.{source_system}.{table_name}
            LIMIT {limit}
        """).to_pandas()
        return df
    except Exception as e:
        return None

def sample_semantic_data(source_system: str, view_name: str, limit: int = 50):
    """
    Sample data from a semantic view's underlying tables.
    Native Semantic Views can't be queried directly with SELECT *.
    We query the primary table referenced in the semantic view definition.
    """
    session = get_session()
    
    try:
        # First, get the semantic view definition to find the primary table
        config_df = session.sql(f"""
            SELECT VIEW_SQL 
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG 
            WHERE SOURCE_SYSTEM = '{source_system}' 
              AND VIEW_NAME = '{view_name}'
              AND IS_ACTIVE = TRUE
        """).to_pandas()
        
        if not config_df.empty:
            view_sql = config_df['VIEW_SQL'].iloc[0]
            
            # Extract the first table reference (pattern: "AS CURATED_DEV.SOURCE.TABLE")
            import re
            table_match = re.search(r'AS\s+(CURATED_DEV\.\w+\.\w+)', view_sql)
            
            if table_match:
                primary_table = table_match.group(1)
                
                # Query the underlying curated table
                df = session.sql(f"""
                    SELECT * 
                    FROM {primary_table}
                    LIMIT {limit}
                """).to_pandas()
                return df
        
        # Fallback: try to query a likely curated table based on view name
        # e.g., SALES_ANALYTICS -> try FACT_SALES_ORDERS or DIM_CUSTOMER
        if 'ANALYTICS' in view_name:
            base_name = view_name.replace('_ANALYTICS', '')
            
            # Try fact table first
            try:
                df = session.sql(f"""
                    SELECT * 
                    FROM CURATED_DEV.{source_system}.FACT_{base_name}
                    LIMIT {limit}
                """).to_pandas()
                return df
            except:
                pass
            
            # Try without prefix
            try:
                df = session.sql(f"""
                    SELECT * 
                    FROM CURATED_DEV.{source_system}.{base_name}
                    LIMIT {limit}
                """).to_pandas()
                return df
            except:
                pass
        
        return None
        
    except Exception as e:
        return None

def get_semantic_view_info(source_system: str, view_name: str):
    """Get information about a semantic view including its dimensions and metrics."""
    session = get_session()
    try:
        config_df = session.sql(f"""
            SELECT VIEW_SQL, VIEW_COMMENT 
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG 
            WHERE SOURCE_SYSTEM = '{source_system}' 
              AND VIEW_NAME = '{view_name}'
              AND IS_ACTIVE = TRUE
        """).to_pandas()
        
        if not config_df.empty:
            view_sql = config_df['VIEW_SQL'].iloc[0]
            comment = config_df['VIEW_COMMENT'].iloc[0] if 'VIEW_COMMENT' in config_df.columns else ''
            
            # Extract dimensions
            import re
            dimensions = []
            if 'DIMENSIONS' in view_sql:
                dim_section = re.search(r'DIMENSIONS\s*\((.*?)\)\s*(?:METRICS|COMMENT|$)', view_sql, re.DOTALL)
                if dim_section:
                    dim_matches = re.findall(r'AS\s+(\w+)', dim_section.group(1))
                    dimensions = dim_matches
            
            # Extract metrics
            metrics = []
            if 'METRICS' in view_sql:
                met_section = re.search(r'METRICS\s*\((.*?)\)\s*(?:COMMENT|$)', view_sql, re.DOTALL)
                if met_section:
                    met_matches = re.findall(r'(\w+)\s+AS\s+', met_section.group(1))
                    metrics = met_matches
            
            # Extract tables
            tables = re.findall(r'(CURATED_DEV\.\w+\.\w+)', view_sql)
            
            return {
                'dimensions': dimensions,
                'metrics': metrics,
                'tables': list(set(tables)),
                'comment': comment
            }
        
        return None
    except:
        return None

def render_source_explorer():
    """Render source system explorer with all three layers"""
    st.markdown("""
    <div class="main-header">
        <h1>🔍 Source System Explorer</h1>
        <p>Browse data across RAW, CURATED, and SEMANTIC layers</p>
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
        
        # Get data for all layers
        raw_tables = get_tables_for_source(selected_source)
        curated_tables = get_curated_stats(selected_source)
        semantic_views = get_semantic_views_for_source(selected_source)
        
        # Layer overview metrics
        col_raw, col_cur, col_sem = st.columns(3)
        with col_raw:
            raw_count = len(raw_tables) if not raw_tables.empty else 0
            st.metric("📦 RAW Tables", raw_count)
        with col_cur:
            cur_count = len(curated_tables) if not curated_tables.empty else 0
            st.metric("⚙️ Curated Tables", cur_count)
        with col_sem:
            sem_count = len(semantic_views) if not semantic_views.empty else 0
            st.metric("📊 Semantic Views", sem_count)
        
        st.divider()
        
        # Tabs for each layer
        tab_raw, tab_curated, tab_semantic, tab_sample = st.tabs([
            "📦 RAW Layer", 
            "⚙️ Curated Layer", 
            "📊 Semantic Layer",
            "🔍 Sample Data"
        ])
        
        with tab_raw:
            st.markdown("#### RAW Tables (SCD Type 2)")
            if not raw_tables.empty:
                st.dataframe(raw_tables, use_container_width=True)
            else:
                st.info("No RAW tables found. Run data load scripts first.")
        
        with tab_curated:
            st.markdown("#### Curated Tables (Dynamic Tables)")
            if not curated_tables.empty:
                # Show dimensions and facts separately
                dims = curated_tables[curated_tables['TABLE_TYPE'] == 'DIMENSION']
                facts = curated_tables[curated_tables['TABLE_TYPE'] == 'FACT']
                
                col1, col2 = st.columns(2)
                with col1:
                    st.markdown("**Dimensions**")
                    if not dims.empty:
                        st.dataframe(dims[['TABLE_NAME', 'ROW_COUNT']], use_container_width=True)
                    else:
                        st.caption("No dimensions")
                with col2:
                    st.markdown("**Facts**")
                    if not facts.empty:
                        st.dataframe(facts[['TABLE_NAME', 'ROW_COUNT']], use_container_width=True)
                    else:
                        st.caption("No facts")
            else:
                st.info("No curated tables found. Run BUILD_CURATED_LAYER() first.")
        
        with tab_semantic:
            st.markdown("#### Semantic Views (Cortex Analyst Ready)")
            if not semantic_views.empty:
                st.dataframe(semantic_views, use_container_width=True)
                
                st.divider()
                st.markdown("**Use with Cortex Analyst:**")
                st.code(f"SELECT * FROM SEM_DEV.{selected_source}.<VIEW_NAME>", language="sql")
            else:
                st.info("No semantic views found. Run BUILD_SEMANTIC_LAYER() first.")
        
        with tab_sample:
            st.markdown("#### Sample Data Explorer")
            
            # Layer filter
            layer_options = ["RAW", "CURATED", "SEMANTIC"]
            selected_layer = st.radio(
                "Select Layer",
                layer_options,
                horizontal=True,
                key="sample_layer"
            )
            
            # Table/View selector based on layer
            if selected_layer == "RAW":
                if not raw_tables.empty:
                    table_options = raw_tables['TABLE_NAME'].tolist()
                    selected_object = st.selectbox(
                        "Select Table",
                        table_options,
                        key="raw_table_select"
                    )
                    
                    col1, col2 = st.columns([1, 4])
                    with col1:
                        sample_limit = st.number_input("Rows", min_value=10, max_value=500, value=50, step=10)
                    with col2:
                        st.write("")
                        if st.button("🔍 Load Sample Data", key="load_raw"):
                            with st.spinner("Loading RAW data..."):
                                sample_df = sample_table_data(selected_source, selected_object, sample_limit)
                                if sample_df is not None and not isinstance(sample_df, tuple):
                                    st.success(f"Loaded {len(sample_df)} rows from RAW_DEV.{selected_source}.{selected_object}")
                                    st.dataframe(sample_df, use_container_width=True)
                                else:
                                    st.error("Could not load sample data")
                else:
                    st.info("No RAW tables available")
            
            elif selected_layer == "CURATED":
                if not curated_tables.empty:
                    table_options = curated_tables['TABLE_NAME'].tolist()
                    selected_object = st.selectbox(
                        "Select Table",
                        table_options,
                        key="curated_table_select"
                    )
                    
                    col1, col2 = st.columns([1, 4])
                    with col1:
                        sample_limit = st.number_input("Rows", min_value=10, max_value=500, value=50, step=10, key="cur_limit")
                    with col2:
                        st.write("")
                        if st.button("🔍 Load Sample Data", key="load_curated"):
                            with st.spinner("Loading CURATED data..."):
                                sample_df = sample_curated_data(selected_source, selected_object, sample_limit)
                                if sample_df is not None:
                                    st.success(f"Loaded {len(sample_df)} rows from CURATED_DEV.{selected_source}.{selected_object}")
                                    st.dataframe(sample_df, use_container_width=True)
                                else:
                                    st.error("Could not load sample data")
                else:
                    st.info("No CURATED tables available. Run BUILD_CURATED_LAYER() first.")
            
            elif selected_layer == "SEMANTIC":
                if not semantic_views.empty:
                    view_options = semantic_views['VIEW_NAME'].tolist()
                    selected_object = st.selectbox(
                        "Select Semantic View",
                        view_options,
                        key="semantic_view_select"
                    )
                    
                    # Show semantic view metadata
                    view_info = get_semantic_view_info(selected_source, selected_object)
                    if view_info:
                        with st.expander("📋 Semantic View Details", expanded=False):
                            if view_info.get('comment'):
                                st.caption(view_info['comment'])
                            
                            col_d, col_m = st.columns(2)
                            with col_d:
                                st.markdown("**Dimensions:**")
                                if view_info.get('dimensions'):
                                    for dim in view_info['dimensions']:
                                        st.markdown(f"- `{dim}`")
                                else:
                                    st.caption("None defined")
                            with col_m:
                                st.markdown("**Metrics:**")
                                if view_info.get('metrics'):
                                    for met in view_info['metrics']:
                                        st.markdown(f"- `{met}`")
                                else:
                                    st.caption("None defined")
                            
                            if view_info.get('tables'):
                                st.markdown("**Underlying Tables:**")
                                for tbl in view_info['tables']:
                                    st.markdown(f"- `{tbl}`")
                    
                    st.divider()
                    
                    # Natural language query for semantic view
                    st.markdown("**Query with Natural Language:**")
                    semantic_question = st.text_input(
                        "Ask a question",
                        placeholder="e.g., Show me a summary of the data",
                        key="semantic_question_input",
                        label_visibility="collapsed"
                    )
                    
                    if st.button("🤖 Query via Cortex", key="query_semantic"):
                        if semantic_question:
                            with st.spinner("Querying semantic view via Cortex Analyst..."):
                                semantic_view_path = f"{selected_source}.{selected_object}"
                                api_response, error = call_cortex_analyst(semantic_question, semantic_view_path)
                                
                                if error:
                                    st.error(f"Error: {error}")
                                elif api_response:
                                    msg_content = api_response.get("message", {}).get("content", [])
                                    sql_query = None
                                    explanation = ""
                                    
                                    for part in msg_content:
                                        if part.get("type") == "text":
                                            explanation += part.get("text", "")
                                        elif part.get("type") == "sql":
                                            sql_query = part.get("statement", "")
                                    
                                    if explanation:
                                        st.info(explanation)
                                    
                                    if sql_query:
                                        with st.expander("Generated SQL", expanded=False):
                                            st.code(sql_query, language="sql")
                                        
                                        result_df, sql_error = execute_sql(sql_query)
                                        if sql_error:
                                            st.error(f"SQL Error: {sql_error}")
                                        elif result_df is not None:
                                            st.success(f"Returned {len(result_df)} rows")
                                            st.dataframe(result_df, use_container_width=True)
                        else:
                            st.warning("Please enter a question")
                    
                    # Quick direct queries (no LLM needed)
                    st.divider()
                    st.markdown("**Quick Data Preview:**")
                    
                    # Get underlying table for direct queries
                    underlying_tables = get_underlying_tables_for_semantic_view(f"{selected_source}.{selected_object}")
                    
                    if underlying_tables:
                        primary_table = underlying_tables[0]
                        
                        col_a, col_b, col_c = st.columns(3)
                        with col_a:
                            if st.button("📋 Sample Data", key="sem_sample_data", use_container_width=True):
                                with st.spinner("Loading..."):
                                    result_df, error = execute_sql(f"SELECT * FROM {primary_table} LIMIT 50")
                                    if error:
                                        st.error(f"Error: {error}")
                                    elif result_df is not None:
                                        st.success(f"Sample from {primary_table}")
                                        st.dataframe(result_df, use_container_width=True)
                        
                        with col_b:
                            if st.button("🔢 Row Count", key="sem_count", use_container_width=True):
                                with st.spinner("Counting..."):
                                    result_df, error = execute_sql(f"SELECT COUNT(*) as TOTAL_ROWS FROM {primary_table}")
                                    if error:
                                        st.error(f"Error: {error}")
                                    elif result_df is not None:
                                        count = result_df['TOTAL_ROWS'].iloc[0]
                                        st.metric("Total Rows", f"{count:,}")
                        
                        with col_c:
                            if st.button("📊 Column Info", key="sem_cols", use_container_width=True):
                                with st.spinner("Loading schema..."):
                                    try:
                                        sess = get_session()
                                        sample = sess.sql(f"SELECT * FROM {primary_table} LIMIT 1").to_pandas()
                                        col_info = pd.DataFrame({
                                            'Column': sample.columns,
                                            'Type': [str(sample[c].dtype) for c in sample.columns]
                                        })
                                        st.dataframe(col_info, use_container_width=True)
                                    except Exception as e:
                                        st.error(f"Error: {e}")
                    else:
                        st.info("Could not find underlying tables for quick queries.")
                else:
                    st.info("No SEMANTIC views available. Run BUILD_SEMANTIC_LAYER() first.")

# ============================================================================
# PAGE: CORTEX ANALYST
# ============================================================================

def call_cortex_analyst(prompt: str, semantic_view: str):
    """
    Calls the Cortex Analyst API for natural language to SQL on semantic views.
    Uses the internal REST client, with CORTEX.COMPLETE fallback.
    """
    session = get_session()
    
    # Try internal REST client (works in Streamlit in Snowflake)
    try:
        # Get the REST client from the Snowpark session connection
        rest = session._conn._rest
        
        # API Endpoint for Cortex Analyst
        endpoint = "/api/v2/cortex/analyst/message"
        
        # Payload - use "semantic_view" key for semantic views
        request_body = {
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": prompt}]}
            ],
            "semantic_view": f"SEM_DEV.{semantic_view}"
        }
        
        # Use the internal REST client to make the call
        response = rest.request(
            url=endpoint,
            method="POST",
            body=request_body,
            headers={"Content-Type": "application/json"}
        )
        
        if response and 'message' in response:
            return response, None
        else:
            # Empty response - try fallback
            return call_cortex_complete_fallback(prompt, semantic_view)
            
    except AttributeError:
        # _rest doesn't exist - use fallback
        return call_cortex_complete_fallback(prompt, semantic_view)
    except Exception as e:
        # Any other error - use fallback
        return call_cortex_complete_fallback(prompt, semantic_view)

def get_semantic_view_metadata(semantic_view: str) -> str:
    """Get dimensions and metrics for a semantic view from the config table."""
    session = get_session()
    
    try:
        # Parse source system and view name
        parts = semantic_view.split('.')
        if len(parts) >= 2:
            source_system = parts[0]
            view_name = parts[1] if len(parts) == 2 else parts[-1]
        else:
            return ""
        
        # Query the semantic config to get the view definition
        result = session.sql(f"""
            SELECT VIEW_SQL 
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG 
            WHERE SOURCE_SYSTEM = '{source_system}' 
              AND VIEW_NAME = '{view_name}'
              AND IS_ACTIVE = TRUE
        """).to_pandas()
        
        if not result.empty:
            view_sql = result['VIEW_SQL'].iloc[0]
            
            # Extract dimensions and metrics from the SQL
            dimensions = []
            metrics = []
            
            # Parse DIMENSIONS section
            if 'DIMENSIONS' in view_sql:
                dim_start = view_sql.find('DIMENSIONS')
                dim_end = view_sql.find('METRICS', dim_start) if 'METRICS' in view_sql[dim_start:] else view_sql.find(')', dim_start)
                dim_section = view_sql[dim_start:dim_end]
                
                # Extract AS aliases (these are the dimension names to use)
                import re
                dim_matches = re.findall(r'AS\s+(\w+)', dim_section)
                dimensions = dim_matches
            
            # Parse METRICS section
            if 'METRICS' in view_sql:
                met_start = view_sql.find('METRICS')
                met_end = view_sql.find('COMMENT', met_start) if 'COMMENT' in view_sql[met_start:] else len(view_sql)
                met_section = view_sql[met_start:met_end]
                
                # Extract metric names (before AS)
                import re
                met_matches = re.findall(r'(\w+)\.\w+\s+AS', met_section)
                # Also get the metric aliases
                met_aliases = re.findall(r'AS\s+(\w+)', met_section)
                metrics = met_aliases if met_aliases else met_matches
            
            if dimensions or metrics:
                return f"""Available columns (use exactly as shown, case-sensitive):
DIMENSIONS: {', '.join(dimensions)}
METRICS: {', '.join(metrics)}"""
        
        return ""
    except Exception:
        return ""

def get_underlying_tables_for_semantic_view(semantic_view: str) -> list:
    """Get the underlying curated tables for a semantic view."""
    session = get_session()
    try:
        parts = semantic_view.split('.')
        if len(parts) >= 2:
            source_system = parts[0]
            view_name = parts[-1]
        else:
            return []
        
        result = session.sql(f"""
            SELECT VIEW_SQL 
            FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG 
            WHERE SOURCE_SYSTEM = '{source_system}' 
              AND VIEW_NAME = '{view_name}'
              AND IS_ACTIVE = TRUE
        """).to_pandas()
        
        if not result.empty:
            view_sql = result['VIEW_SQL'].iloc[0]
            import re
            tables = re.findall(r'(CURATED_DEV\.\w+\.\w+)', view_sql)
            return list(set(tables))
        return []
    except:
        return []

def call_cortex_complete_fallback(prompt: str, semantic_view: str):
    """Fallback using CORTEX.COMPLETE SQL function to generate SQL against curated tables."""
    session = get_session()
    
    try:
        # Get the underlying curated tables for this semantic view
        underlying_tables = get_underlying_tables_for_semantic_view(semantic_view)
        
        if not underlying_tables:
            return None, "Could not find underlying tables for this semantic view."
        
        # Use the first (primary) table
        primary_table = underlying_tables[0]
        
        # Get actual column info by sampling the table
        try:
            sample_df = session.sql(f"SELECT * FROM {primary_table} LIMIT 1").to_pandas()
            columns = list(sample_df.columns)
            # Format columns for the prompt - these are the exact column names
            columns_str = ', '.join(columns[:25])  # Limit to first 25 columns
        except:
            columns_str = "*"
            columns = []
        
        # Escape single quotes for SQL
        escaped_prompt = prompt.replace("'", "''")
        escaped_table = primary_table.replace("'", "''")
        
        # Build prompt to query the underlying curated table
        system_prompt = f"""Generate a Snowflake SQL query.

TABLE: {escaped_table}
COLUMNS: {columns_str}

Question: {escaped_prompt}

IMPORTANT:
- Use SELECT with specific columns or COUNT(*)
- Table name is exactly: {escaped_table}
- Add LIMIT 100 at the end
- Return ONLY SQL, nothing else

Example for "show summary": SELECT * FROM {escaped_table} LIMIT 100
Example for "count by X": SELECT X, COUNT(*) as cnt FROM {escaped_table} GROUP BY X LIMIT 100"""
        
        # Use CORTEX.COMPLETE via SQL to generate SQL
        result = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                'llama3.1-70b',
                '{system_prompt.replace("'", "''")}'
            ) AS response
        """).to_pandas()
        
        if not result.empty and result['RESPONSE'].iloc[0]:
            sql = result['RESPONSE'].iloc[0].strip()
            
            # Clean up the SQL - remove markdown code blocks
            if '```' in sql:
                parts = sql.split('```')
                for part in parts:
                    if 'SELECT' in part.upper():
                        sql = part.strip()
                        if sql.lower().startswith('sql'):
                            sql = sql[3:].strip()
                        break
            
            # Remove trailing content after semicolon
            if ';' in sql:
                sql = sql.split(';')[0] + ';'
            
            # Ensure it starts with SELECT
            if not sql.upper().strip().startswith('SELECT'):
                upper_sql = sql.upper()
                select_idx = upper_sql.find('SELECT')
                if select_idx >= 0:
                    sql = sql[select_idx:]
            
            # Return in the same format as Cortex Analyst API
            return {
                "message": {
                    "content": [
                        {"type": "text", "text": "Here's the query for your question:"},
                        {"type": "sql", "statement": sql}
                    ]
                }
            }, None
        else:
            return None, "Could not generate SQL query. Please try rephrasing your question."
            
    except Exception as e:
        return None, f"Error generating query: {str(e)}"

def execute_sql(sql: str):
    """Execute SQL and return DataFrame"""
    session = get_session()
    try:
        return session.sql(sql).to_pandas(), None
    except Exception as e:
        return None, str(e)

def process_question(prompt: str, semantic_view: str):
    """Process a user question via Cortex Analyst API"""
    
    # Add to chat history
    st.session_state.cortex_history.append({
        "role": "user",
        "content": prompt
    })
    
    # Call Cortex Analyst
    api_response, error = call_cortex_analyst(prompt, semantic_view)
    
    if error:
        st.session_state.cortex_history.append({
            "role": "assistant",
            "content": f"❌ {error}",
            "sql": None,
            "df": None
        })
        return
    
    if api_response:
        msg_content = api_response.get("message", {}).get("content", [])
        sql_query = None
        explanation = ""
        
        for part in msg_content:
            if part.get("type") == "text":
                explanation += part.get("text", "")
            elif part.get("type") == "sql":
                sql_query = part.get("statement", "")
        
        result_df = None
        if sql_query:
            result_df, sql_error = execute_sql(sql_query)
            if sql_error:
                explanation += f"\n\n⚠️ SQL Error: {sql_error}"
        
        st.session_state.cortex_history.append({
            "role": "assistant",
            "content": explanation if explanation else "✅ Query executed successfully",
            "sql": sql_query,
            "df": result_df
        })

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
        col1, col2 = st.columns([3, 1])
        
        with col1:
            # Create view selector
            view_options = sem_views.apply(
                lambda x: f"{x['SOURCE_SYSTEM']}.{x['VIEW_NAME']}", axis=1
            ).tolist()
            
            selected_view = st.selectbox("Select Semantic View", view_options, help="Choose which semantic view to query")
        
        with col2:
            st.write("")
            if st.button("🔄 Refresh", use_container_width=True):
                st.cache_data.clear()
                st.experimental_rerun()
        
        st.divider()
        
        # Initialize chat history
        if "cortex_history" not in st.session_state:
            st.session_state.cortex_history = []
        
        # Display chat history
        for i, chat in enumerate(st.session_state.cortex_history):
            if chat["role"] == "user":
                st.markdown(f"""
                <div class="chat-bubble" style="background: #E3F5FC; border-left: 5px solid #29B5E8; padding: 15px; border-radius: 12px; margin-bottom: 10px;">
                    <strong>👤 You</strong><br>{chat["content"]}
                </div>
                """, unsafe_allow_html=True)
            else:
                st.markdown(f"""
                <div class="chat-bubble" style="background: #F1F5F9; border-left: 5px solid #6E56CF; padding: 15px; border-radius: 12px; margin-bottom: 10px;">
                    <strong>🤖 Cortex Analyst</strong><br>{chat["content"]}
                </div>
                """, unsafe_allow_html=True)
                if chat.get("sql"):
                    with st.expander("View Generated SQL", expanded=False):
                        st.code(chat["sql"], language="sql")
                if chat.get("df") is not None and not chat["df"].empty:
                    st.dataframe(chat["df"], use_container_width=True)
        
        # Sample questions (only show if no chat history)
        if not st.session_state.cortex_history:
            source = selected_view.split('.')[0] if selected_view else ""
            
            sample_questions = {
                "SAP": ["Show total sales by customer country", "List top 10 vendors by purchase amount", "Count customers by region"],
                "SALESFORCE": ["Show opportunities by stage", "Count accounts by industry", "List top opportunities by amount"],
                "ORACLE": ["Show invoices by vendor", "Total order amount by period", "Count orders by status"],
                "FHIR": ["Count patients by gender", "Show encounters by type", "List claims by status"],
                "WORKDAY": ["Count employees by department", "Show compensation by job level", "List time off by type"],
                "SERVICENOW": ["Count incidents by priority", "Show changes by status", "List problems by category"]
            }
            
            st.markdown("#### 💡 Sample Questions")
            questions = sample_questions.get(source, ["Show me a summary of the data"])
            cols = st.columns(min(len(questions), 3))
            for i, q in enumerate(questions):
                with cols[i % 3]:
                    if st.button(f"💬 {q}", key=f"sample_{i}", use_container_width=True):
                        process_question(q, selected_view)
                        st.experimental_rerun()
        
        st.divider()
        
        # Question input
        col_input, col_btn = st.columns([5, 1])
        with col_input:
            user_question = st.text_input(
                "Ask a question", 
                placeholder="Ask a question about your data...",
                label_visibility="collapsed",
                key="question_input"
            )
        with col_btn:
            ask_clicked = st.button("🚀 Ask", use_container_width=True)
        
        # Process question
        if ask_clicked and user_question:
            process_question(user_question, selected_view)
            st.experimental_rerun()
        
        # Clear chat button
        if st.session_state.cortex_history:
            if st.button("🗑️ Clear Chat", key="clear_chat"):
                st.session_state.cortex_history = []
                st.experimental_rerun()
        
    else:
        st.warning("No semantic views found. Run BUILD_SEMANTIC_LAYER() first.")
        
        st.markdown("""
        ### Setup Instructions
        
        To enable Cortex Analyst, run the following SQL:
        
        ```sql
        -- Build semantic layer for all sources
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SAP');
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SALESFORCE');
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('ORACLE');
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('FHIR');
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('WORKDAY');
        CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SERVICENOW');
        ```
        """)

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
            # Drop duplicates to avoid duplicate widget keys
            contracts = contracts.drop_duplicates(subset=['CONTRACT_ID'])
            
            for idx, (_, contract) in enumerate(contracts.iterrows()):
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
                
                if st.button(f"Details", key=f"detail_{idx}_{contract_id}", use_container_width=True):
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
    
    # Get contract health info first (this is the source of truth from VW_CONTRACT_HEALTH)
    contracts_df = get_contract_details()
    contract_health = contracts_df[contracts_df['CONTRACT_ID'] == contract_id]
    
    if contract_health.empty:
        st.warning(f"Contract not found: {contract_id}")
        if st.button("← Back to List"):
            st.session_state.selected_contract = None
            st.experimental_rerun()
        return
    
    health = contract_health.iloc[0]
    
    # Try to get additional registry info (optional)
    registry = get_contract_registry_detail(contract_id)
    has_registry = not registry.empty
    contract = registry.iloc[0] if has_registry else None
    
    # Get display values - prefer registry, fallback to health view
    contract_name = contract['CONTRACT_NAME'] if has_registry else health['CONTRACT_NAME']
    source_system = contract['SOURCE_SYSTEM'] if has_registry else health['SOURCE_SYSTEM']
    source_table = contract['SOURCE_TABLE'] if has_registry else health['SOURCE_TABLE']
    
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
        <h3 style="margin: 0;">{icon} {contract_name}</h3>
        <p style="margin: 0.5rem 0 0 0; color: #94A3B8;">
            {source_system} • {source_table} • {desc}
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
        
        if has_registry:
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
        else:
            st.markdown(f"""
            | Property | Value |
            |----------|-------|
            | **Contract ID** | `{contract_id}` |
            | **Source System** | {source_system} |
            | **Source Table** | {source_table} |
            | **Health Status** | {status} |
            | **Last Validation** | {health['LAST_VALIDATION']} |
            """)
            st.info("Full contract registry details not available.")
    
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
