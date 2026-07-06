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
import plotly.graph_objects as go
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
             "🔮 Governance", "🌟 Horizon Context", "📋 Contracts", "ℹ️ About"],
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
# HORIZON CONTEXT (SELECT STAR) — DATA FUNCTIONS
# ============================================================================

_HC = 'CURATED_DEV.HORIZON_CONTEXT'

@st.cache_data(ttl=30)
def get_connector_status():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT CONNECTOR_ID, SOURCE_SYSTEM, SOURCE_TYPE, CONNECTION_NAME,
                   STATUS, CRAWL_FREQUENCY, LAST_CRAWL_AT, NEXT_CRAWL_AT,
                   OBJECTS_TOTAL, TABLES_DISCOVERED, COLUMNS_DISCOVERED,
                   DASHBOARDS_DISCOVERED, MODELS_DISCOVERED,
                   CONNECTOR_ICON, CONNECTOR_COLOR,
                   IS_PRPR_AVAILABLE, ROADMAP_NOTE, ERROR_MESSAGE
            FROM {_HC}.EXT_CONNECTORS
            ORDER BY IS_PRPR_AVAILABLE DESC, STATUS, SOURCE_SYSTEM
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_unified_catalog(search_query='', obj_type=None, source=None, sensitivity=None):
    session = get_session()
    try:
        where_clauses = ["1=1"]
        if search_query:
            q = search_query.replace("'", "''")
            where_clauses.append(
                f"(UPPER(QUALIFIED_NAME) LIKE UPPER('%{q}%') "
                f"OR UPPER(DESCRIPTION) LIKE UPPER('%{q}%') "
                f"OR UPPER(TABLE_NAME) LIKE UPPER('%{q}%'))"
            )
        if obj_type and obj_type != 'All':
            where_clauses.append(f"OBJECT_TYPE = '{obj_type}'")
        if source and source != 'All':
            src = source.replace("'", "''")
            where_clauses.append(f"SOURCE_SYSTEM = '{src}'")
        if sensitivity and sensitivity != 'All':
            sen = sensitivity.replace("'", "''")
            where_clauses.append(f"SENSITIVITY_CLASS = '{sen}'")

        where_sql = ' AND '.join(where_clauses)
        return session.sql(f"""
            SELECT CONNECTOR_ICON, SOURCE_SYSTEM, SOURCE_LAYER, OBJECT_TYPE,
                   QUALIFIED_NAME, TABLE_NAME, COLUMN_NAME,
                   DESCRIPTION, SENSITIVITY_CLASS, IS_PII, PII_TYPE,
                   POPULARITY_SCORE, QUERY_COUNT_30D, USER_COUNT_30D,
                   DOWNSTREAM_BI_COUNT, OWNER_EMAIL, OWNER_TEAM,
                   HAS_GOVERNANCE_GAP, IS_ORPHANED, GOVERNANCE_GAP_SCORE,
                   CONNECTOR_COLOR, OBJECT_ID
            FROM {_HC}.V_UNIFIED_CATALOG
            WHERE {where_sql}
            ORDER BY POPULARITY_SCORE DESC NULLS LAST
            LIMIT 200
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_lineage_full():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT LINEAGE_ID, LINEAGE_PATH_ID, HOP_NUMBER,
                   SOURCE_OBJECT_ID, SOURCE_QUALIFIED_NAME, SOURCE_PLATFORM,
                   SOURCE_LAYER, SOURCE_TABLE, SOURCE_ICON, SOURCE_COLOR,
                   TARGET_OBJECT_ID, TARGET_QUALIFIED_NAME, TARGET_PLATFORM,
                   TARGET_LAYER, TARGET_TABLE, TARGET_ICON, TARGET_COLOR,
                   LINEAGE_TYPE, TRANSFORMATION_DESC, CONFIDENCE_SCORE
            FROM {_HC}.V_CROSS_PLATFORM_LINEAGE
            ORDER BY LINEAGE_PATH_ID, HOP_NUMBER
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_usage_intelligence():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT OBJECT_ID, QUALIFIED_NAME, SOURCE_SYSTEM, SOURCE_LAYER,
                   OBJECT_TYPE, POPULARITY_SCORE, QUERY_COUNT_30D, USER_COUNT_30D,
                   DOWNSTREAM_BI_COUNT, IS_ORPHANED, OWNER_EMAIL, OWNER_TEAM,
                   CONNECTOR_ICON, CONNECTOR_COLOR,
                   TOTAL_QUERIES_14D, PEAK_DAILY_QUERIES, AVG_DAILY_QUERIES,
                   TOTAL_BI_VIEWS_14D, AVG_FRESHNESS_HOURS, POPULARITY_TIER
            FROM {_HC}.V_USAGE_INTELLIGENCE
            ORDER BY POPULARITY_SCORE DESC NULLS LAST
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=300)
def get_usage_trends():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT us.STAT_DATE, us.OBJECT_ID, us.QUERY_COUNT, us.DISTINCT_USERS,
                   us.BI_VIEWS, obj.TABLE_NAME, obj.SOURCE_SYSTEM, c.CONNECTOR_COLOR
            FROM {_HC}.EXT_USAGE_STATS us
            JOIN {_HC}.EXT_CATALOG_OBJECTS obj ON us.OBJECT_ID = obj.OBJECT_ID
            JOIN {_HC}.EXT_CONNECTORS c ON obj.CONNECTOR_ID = c.CONNECTOR_ID
            WHERE us.STAT_DATE >= DATEADD(day, -14, CURRENT_DATE())
            ORDER BY us.STAT_DATE DESC, us.QUERY_COUNT DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_governance_recommendations():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT r.REC_ID, r.OBJECT_ID, r.RECOMMENDATION_TYPE, r.PRIORITY,
                   r.REASON, r.SUGGESTED_VALUE, r.AI_CONFIDENCE, r.STATUS,
                   r.CREATED_AT, o.QUALIFIED_NAME, o.SOURCE_SYSTEM, o.OBJECT_TYPE,
                   o.POPULARITY_SCORE, o.IS_PII, c.CONNECTOR_ICON
            FROM {_HC}.EXT_GOVERNANCE_RECOMMENDATIONS r
            JOIN {_HC}.EXT_CATALOG_OBJECTS o ON r.OBJECT_ID = o.OBJECT_ID
            JOIN {_HC}.EXT_CONNECTORS c ON o.CONNECTOR_ID = c.CONNECTOR_ID
            WHERE r.STATUS = 'OPEN'
            ORDER BY
                CASE r.PRIORITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
                o.POPULARITY_SCORE DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_governance_gaps():
    session = get_session()
    try:
        return session.sql(f"""
            SELECT OBJECT_ID, OBJECT_TYPE, QUALIFIED_NAME, SOURCE_SYSTEM, SOURCE_LAYER,
                   SENSITIVITY_CLASS, IS_PII, PII_TYPE, POPULARITY_SCORE, QUERY_COUNT_30D,
                   OWNER_EMAIL, IS_ORPHANED, CONNECTOR_ICON,
                   MISSING_DESCRIPTION, MISSING_OWNER, MISSING_SENSITIVITY, UNDECLARED_PII,
                   GOVERNANCE_RISK_SCORE, OPEN_RECOMMENDATIONS
            FROM {_HC}.V_GOVERNANCE_GAPS
            ORDER BY GOVERNANCE_RISK_SCORE DESC
            LIMIT 50
        """).to_pandas()
    except Exception:
        return pd.DataFrame()

def hc_simulate_crawl(connector_id):
    session = get_session()
    try:
        result = session.sql(
            f"CALL {_HC}.SP_SIMULATE_CONNECTOR_CRAWL('{connector_id}')"
        ).to_pandas()
        get_connector_status.clear()
        return result.iloc[0, 0] if not result.empty else 'Crawl complete.'
    except Exception as e:
        return f'Error: {str(e)}'

def hc_apply_recommendation(rec_id, applied_by='DATA_STEWARD'):
    session = get_session()
    try:
        result = session.sql(
            f"CALL {_HC}.SP_APPLY_RECOMMENDATION('{rec_id}', '{applied_by}')"
        ).to_pandas()
        get_governance_recommendations.clear()
        get_governance_gaps.clear()
        return result.iloc[0, 0] if not result.empty else 'Applied.'
    except Exception as e:
        return f'Error: {str(e)}'

def hc_enrich_with_cortex(object_id, table_name, col_name, source_system, obj_type):
    session = get_session()
    try:
        if col_name and str(col_name).strip():
            prompt = (
                f"Generate a concise 1-2 sentence data catalog description for the column "
                f"'{col_name}' in table '{table_name}' from {source_system}. "
                f"Focus on business meaning, typical values, and analytics use cases. Plain text only."
            )
        else:
            prompt = (
                f"Generate a concise 1-2 sentence data catalog description for the "
                f"{'BI dashboard' if obj_type in ('DASHBOARD','REPORT') else 'database table'} "
                f"'{table_name}' from {source_system}. "
                f"Focus on business purpose and what it contains. Plain text only."
            )
        prompt_esc = prompt.replace("'", "''")
        result = session.sql(
            f"SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2', '{prompt_esc}') AS DESC"
        ).to_pandas()
        description = result['DESC'].iloc[0].strip() if not result.empty else None
        if description:
            desc_esc = description.replace("'", "''")
            session.sql(f"""
                UPDATE {_HC}.EXT_CATALOG_OBJECTS
                SET DESCRIPTION = '{desc_esc}',
                    DESCRIPTION_SOURCE = 'AI_GENERATED',
                    HAS_GOVERNANCE_GAP = FALSE,
                    LAST_CRAWLED_AT = CURRENT_TIMESTAMP()
                WHERE OBJECT_ID = '{object_id}'
            """).collect()
            get_unified_catalog.clear()
            get_governance_gaps.clear()
        return description
    except Exception as e:
        return f'Cortex error: {str(e)}'

# ============================================================================
# HORIZON CONTEXT — LINEAGE GRAPH BUILDER
# ============================================================================

def _build_lineage_figure(lineage_df=None, focal_id=None):
    """Build the cross-platform lineage plotly figure."""

    NODE_MAP = {
        'pg-customers':        (0,   4.0, 'customers',           'PostgreSQL',          '#336791', '🐘'),
        'pg-transactions':     (0,   3.0, 'transactions',         'PostgreSQL',          '#336791', '🐘'),
        'sql-journals':        (0,   2.0, 'journal_entries',      'SQL Server',          '#CC2927', '🪟'),
        'sql-headcount':       (0,   1.2, 'headcount',            'SQL Server',          '#CC2927', '🪟'),
        'pg-employees':        (0,   0.4, 'employees',            'PostgreSQL',          '#336791', '🐘'),
        'dbt-stg-cust':        (1.5, 4.0, 'stg_customers',        'dbt Cloud',           '#FF694A', '🔧'),
        'dbt-dim-cust':        (1.5, 3.5, 'dim_customer',         'dbt Cloud',           '#FF694A', '🔧'),
        'dbt-stg-txn':         (1.5, 3.0, 'stg_transactions',     'dbt Cloud',           '#FF694A', '🔧'),
        'dbt-fct-rev':         (1.5, 2.5, 'fct_revenue',          'dbt Cloud',           '#FF694A', '🔧'),
        'dbt-dim-emp':         (1.5, 0.8, 'dim_employee',         'dbt Cloud',           '#FF694A', '🔧'),
        'sf-raw-account':      (3,   4.0, 'SALESFORCE.ACCOUNT',   'Snowflake RAW',       '#1DB4D1', '❄️'),
        'sf-raw-vbak':         (3,   3.0, 'SAP.VBAK',             'Snowflake RAW',       '#1DB4D1', '❄️'),
        'sf-raw-gl':           (3,   2.0, 'ORACLE.GL_JE_HEADERS', 'Snowflake RAW',       '#1DB4D1', '❄️'),
        'sf-raw-workers':      (3,   0.8, 'WORKDAY.WORKERS',      'Snowflake RAW',       '#1DB4D1', '❄️'),
        'sf-curated-dim-cust': (4.5, 4.0, 'DIM_CUSTOMER',         'Snowflake CURATED',   '#29B5E8', '❄️'),
        'sf-curated-fact-rev': (4.5, 3.0, 'FACT_REVENUE',         'Snowflake CURATED',   '#29B5E8', '❄️'),
        'sf-curated-fact-je':  (4.5, 2.0, 'FACT_JOURNAL_ENTRIES', 'Snowflake CURATED',   '#29B5E8', '❄️'),
        'sf-curated-dim-emp':  (4.5, 0.8, 'DIM_EMPLOYEE',         'Snowflake CURATED',   '#29B5E8', '❄️'),
        'sf-sem-revenue':      (6,   3.0, 'REVENUE_SUMMARY',      'Snowflake SEMANTIC',  '#11567F', '❄️'),
        'sf-sem-workforce':    (6,   0.8, 'WORKFORCE_SUMMARY',    'Snowflake SEMANTIC',  '#11567F', '❄️'),
        'tab-cust360':         (7.5, 4.5, 'Customer 360',         'Tableau',             '#E97627', '📊'),
        'pbi-customer':        (7.5, 4.0, 'Customer Report',      'Power BI',            '#B3920E', '📈'),
        'tab-rev-dash':        (7.5, 3.5, 'Revenue Dashboard',    'Tableau',             '#E97627', '📊'),
        'tab-board':           (7.5, 3.0, 'Board KPIs',           'Tableau',             '#E97627', '📊'),
        'pbi-sales':           (7.5, 2.5, 'Sales Analytics',      'Power BI',            '#B3920E', '📈'),
        'pbi-finance':         (7.5, 2.0, 'Finance Monthly',      'Power BI',            '#B3920E', '📈'),
        'tab-finance':         (7.5, 1.5, 'Finance Close',        'Tableau',             '#E97627', '📊'),
        'tab-hr':              (7.5, 0.8, 'HR Analytics',         'Tableau',             '#E97627', '📊'),
        'pbi-hr':              (7.5, 0.2, 'HR Headcount',         'Power BI',            '#B3920E', '📈'),
    }

    EDGE_LIST = [
        ('pg-customers',   'dbt-stg-cust',        'INGESTED'),
        ('dbt-stg-cust',   'sf-raw-account',       'TRANSFORMED'),
        ('dbt-dim-cust',   'sf-curated-dim-cust',  'TRANSFORMED'),
        ('sf-raw-account', 'sf-curated-dim-cust',  'TRANSFORMED'),
        ('sf-curated-dim-cust', 'tab-cust360',     'CONSUMED'),
        ('sf-curated-dim-cust', 'pbi-customer',    'CONSUMED'),
        ('pg-transactions','dbt-stg-txn',          'INGESTED'),
        ('dbt-stg-txn',    'sf-raw-vbak',          'TRANSFORMED'),
        ('dbt-fct-rev',    'sf-curated-fact-rev',  'TRANSFORMED'),
        ('sf-raw-vbak',    'sf-curated-fact-rev',  'TRANSFORMED'),
        ('sf-curated-fact-rev', 'sf-sem-revenue',  'PUBLISHED'),
        ('sf-sem-revenue', 'tab-rev-dash',          'CONSUMED'),
        ('sf-sem-revenue', 'tab-board',             'CONSUMED'),
        ('sf-curated-fact-rev', 'pbi-finance',      'CONSUMED'),
        ('sf-curated-fact-rev', 'pbi-sales',        'CONSUMED'),
        ('sql-journals',   'sf-raw-gl',             'INGESTED'),
        ('sf-raw-gl',      'sf-curated-fact-je',   'TRANSFORMED'),
        ('sf-curated-fact-je', 'pbi-finance',       'CONSUMED'),
        ('sf-curated-fact-je', 'tab-finance',       'CONSUMED'),
        ('sql-headcount',  'sf-raw-workers',        'INGESTED'),
        ('pg-employees',   'sf-raw-workers',        'INGESTED'),
        ('dbt-dim-emp',    'sf-curated-dim-emp',   'TRANSFORMED'),
        ('sf-raw-workers', 'sf-curated-dim-emp',   'TRANSFORMED'),
        ('sf-curated-dim-emp', 'sf-sem-workforce', 'PUBLISHED'),
        ('sf-sem-workforce','tab-hr',               'CONSUMED'),
        ('sf-curated-dim-emp', 'pbi-hr',            'CONSUMED'),
    ]

    LINEAGE_COLORS = {
        'INGESTED':    '#E97627',
        'TRANSFORMED': '#29B5E8',
        'PUBLISHED':   '#11567F',
        'CONSUMED':    '#18794E',
    }

    fig = go.Figure()

    # Swim lane backgrounds
    LANES = [
        ('External Sources',   -0.4, 0.85, '#FEF3F2'),
        ('dbt Pipeline',        1.1, 0.85, '#FFF8F5'),
        ('Snowflake RAW',       2.6, 0.85, '#F0FFFE'),
        ('Snowflake CURATED',   4.1, 0.85, '#EFF9FF'),
        ('Snowflake SEMANTIC',  5.6, 0.85, '#F0F4FF'),
        ('BI Consumers',        7.1, 1.0,  '#FFFBF0'),
    ]
    for label, x0, w, bg in LANES:
        fig.add_shape(type='rect', x0=x0, x1=x0+w, y0=-0.3, y1=5.1,
                      fillcolor=bg, line=dict(width=1, color='#E2E8F0'), layer='below')
        fig.add_annotation(x=x0+w/2, y=5.2, text=f'<b>{label}</b>',
                           showarrow=False, font=dict(size=9, color='#64748B'), align='center')

    # Determine focal path nodes
    focal_nodes = set()
    if focal_id:
        for src, tgt, _ in EDGE_LIST:
            if src == focal_id or tgt == focal_id:
                focal_nodes.update([src, tgt])
        focal_nodes.add(focal_id)

    # Draw edges
    for src_id, tgt_id, edge_type in EDGE_LIST:
        if src_id not in NODE_MAP or tgt_id not in NODE_MAP:
            continue
        sx, sy = NODE_MAP[src_id][0], NODE_MAP[src_id][1]
        tx, ty = NODE_MAP[tgt_id][0], NODE_MAP[tgt_id][1]
        is_highlighted = focal_id and (src_id in focal_nodes and tgt_id in focal_nodes)
        opacity = 1.0 if (not focal_id or is_highlighted) else 0.15
        line_color = LINEAGE_COLORS.get(edge_type, '#94A3B8')
        line_width = 3 if is_highlighted else 1.5

        # Bezier midpoints
        mx = (sx + tx) / 2
        fig.add_trace(go.Scatter(
            x=[sx + 0.06, mx, tx - 0.06],
            y=[sy, (sy + ty) / 2, ty],
            mode='lines',
            line=dict(color=line_color, width=line_width, shape='spline'),
            opacity=opacity,
            hoverinfo='text',
            hovertext=f'{edge_type}: {NODE_MAP[src_id][2]} → {NODE_MAP[tgt_id][2]}',
            showlegend=False,
        ))

    # Draw nodes
    for nid, (nx, ny, label, system, color, icon) in NODE_MAP.items():
        is_focal = focal_id and nid == focal_id
        is_path = focal_id and nid in focal_nodes
        opacity = 1.0 if (not focal_id or is_path) else 0.25
        size = 22 if is_focal else 16 if is_path else 14

        short = label[:18] + '…' if len(label) > 18 else label
        fig.add_trace(go.Scatter(
            x=[nx], y=[ny],
            mode='markers+text',
            marker=dict(size=size, color=color, symbol='circle',
                        line=dict(width=3 if is_focal else 1,
                                  color='white' if is_focal else color)),
            text=[f'<b>{icon}</b>'],
            textposition='middle center',
            textfont=dict(size=9),
            opacity=opacity,
            hoverinfo='text',
            hovertext=f'<b>{label}</b><br>{system}',
            showlegend=False,
            name=nid,
        ))
        fig.add_annotation(x=nx, y=ny - 0.28, text=short, showarrow=False,
                           font=dict(size=8, color='#334155'), align='center',
                           opacity=opacity)

    # Legend
    for etype, ecolor in LINEAGE_COLORS.items():
        fig.add_trace(go.Scatter(
            x=[None], y=[None], mode='lines',
            line=dict(color=ecolor, width=3),
            name=etype.capitalize(), showlegend=True,
        ))

    fig.update_layout(
        showlegend=True,
        legend=dict(orientation='h', yanchor='bottom', y=1.02, xanchor='left', x=0,
                    font=dict(size=10)),
        hovermode='closest',
        height=580,
        margin=dict(l=5, r=5, t=80, b=5),
        plot_bgcolor='white',
        paper_bgcolor='white',
        xaxis=dict(showgrid=False, showticklabels=False, zeroline=False, range=[-0.5, 9]),
        yaxis=dict(showgrid=False, showticklabels=False, zeroline=False, range=[-0.5, 5.5]),
    )
    return fig

# ============================================================================
# PAGE: HORIZON CONTEXT — SELECT STAR INTEGRATION
# ============================================================================

def render_horizon_context_page():
    """Render the Horizon Context / Select Star integration demo."""
    st.markdown("""
    <div class="main-header">
        <h1>🌟 Horizon Context <span style="font-weight:400;font-size:0.9em;">powered by Select Star</span></h1>
        <p>Cross-platform metadata catalog · External lineage · Usage intelligence · AI governance enrichment</p>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("""
    <div style="background:#EFF9FF;border-radius:12px;padding:1rem 1.5rem;border-left:4px solid #29B5E8;margin-bottom:1rem;">
    <strong>What is Horizon Context?</strong> Snowflake acquired Select Star (Dec 2025) to extend Horizon beyond
    Snowflake-native assets. The integrated product — Horizon Context — connects to external databases, BI tools,
    and data pipelines, harvests their metadata, and surfaces a unified catalog, cross-platform lineage,
    usage intelligence, and AI-powered governance enrichment — all inside Snowflake.
    PrPr launched at Summit 2026 with connectors for PostgreSQL, SQL Server, Tableau, Power BI, and dbt.
    </div>
    """, unsafe_allow_html=True)

    # Top metrics
    connectors_df = get_connector_status()
    active = len(connectors_df[connectors_df['STATUS'] == 'ACTIVE']) if not connectors_df.empty else 5
    total_obj = int(connectors_df['OBJECTS_TOTAL'].sum()) if not connectors_df.empty else 2958
    catalog_df = get_unified_catalog()
    gaps_df = get_governance_gaps()
    gap_count = len(gaps_df) if not gaps_df.empty else 0

    m1, m2, m3, m4, m5 = st.columns(5)
    for col, val, label, hint in [
        (m1, active, 'Active Connectors', '5 PrPr · 2 PuPr planned'),
        (m2, total_obj, 'Objects Cataloged', 'Across all connected systems'),
        (m3, len(catalog_df), 'Catalog Entries', 'Searchable in Universal Search'),
        (m4, gap_count, 'Governance Gaps', 'Missing owner/desc/tags'),
        (m5, 27, 'Lineage Paths', 'Cross-platform edge count'),
    ]:
        col.markdown(f"""
        <div class="metric-card">
            <div style="font-size:1.6rem;font-weight:700;color:#29B5E8;">{val:,}</div>
            <strong>{label}</strong><br>
            <small style="color:#64748B;">{hint}</small>
        </div>
        """, unsafe_allow_html=True)

    st.divider()

    tab_hub, tab_catalog, tab_lineage, tab_usage, tab_ai = st.tabs([
        "🔌 Connector Hub",
        "🔍 Universal Catalog",
        "🗺️ Cross-Platform Lineage",
        "📊 Usage Intelligence",
        "✨ AI Governance",
    ])

    # ── TAB 1: Connector Hub ──────────────────────────────────────────────────
    with tab_hub:
        st.markdown("### Connected External Systems")
        st.caption("Horizon Context metadata connectors — credentials held by Snowflake GS, not shown here")

        if connectors_df.empty:
            st.info("Run `sql/17_select_star_horizon_context.sql` to set up the Horizon Context schema.")
        else:
            for _, chunk in connectors_df.groupby('IS_PRPR_AVAILABLE', sort=False):
                for i in range(0, len(chunk), 4):
                    row_cols = st.columns(4)
                    for j, (_, row) in enumerate(chunk.iloc[i:i+4].iterrows()):
                        with row_cols[j]:
                            status = row.get('STATUS', 'UNKNOWN')
                            status_color = {'ACTIVE':'#18794E','CRAWLING':'#0EA5E9',
                                            'PAUSED':'#AD5700','ERROR':'#CD2B31'}.get(status, '#64748B')
                            status_bg   = {'ACTIVE':'#F0FDF4','CRAWLING':'#F0F9FF',
                                            'PAUSED':'#FFFBEB','ERROR':'#FFF1F2'}.get(status, '#F8FAFC')
                            icon = row.get('CONNECTOR_ICON', '🔌') or '🔌'
                            color = row.get('CONNECTOR_COLOR', '#29B5E8') or '#29B5E8'
                            obj_total = int(row.get('OBJECTS_TOTAL') or 0)
                            last_crawl = row.get('LAST_CRAWL_AT')
                            if pd.notna(last_crawl):
                                delta = pd.Timestamp.now() - pd.Timestamp(last_crawl)
                                mins = int(delta.total_seconds() / 60)
                                crawl_str = (f'{mins}m ago' if mins < 60
                                             else f'{mins//60}h ago' if mins < 1440
                                             else f'{mins//1440}d ago')
                            else:
                                crawl_str = 'Not yet crawled'

                            st.markdown(f"""
                            <div style="background:white;border-radius:12px;padding:1rem;
                                        border-left:4px solid {color};border:1px solid #E2E8F0;
                                        margin-bottom:0.5rem;">
                                <div style="font-size:1.6rem;">{icon}</div>
                                <strong>{row['SOURCE_SYSTEM']}</strong><br>
                                <small style="color:#64748B;">{row.get('CONNECTION_NAME','')}</small><br>
                                <span style="background:{status_bg};color:{status_color};
                                             padding:2px 8px;border-radius:12px;font-size:0.78rem;
                                             font-weight:600;">{status}</span><br>
                                <div style="margin-top:0.5rem;font-size:0.85rem;">
                                    <b>{obj_total:,}</b> objects &nbsp;·&nbsp;
                                    <span style="color:#64748B;">{crawl_str}</span>
                                </div>
                            </div>
                            """, unsafe_allow_html=True)

                            if status == 'ACTIVE':
                                if st.button(f"↻ Crawl", key=f"crawl_{row['CONNECTOR_ID']}",
                                             use_container_width=True):
                                    with st.spinner(f"Crawling {row['SOURCE_SYSTEM']}…"):
                                        msg = hc_simulate_crawl(row['CONNECTOR_ID'])
                                    st.success(msg)
                                    st.rerun()
                            elif row.get('ROADMAP_NOTE'):
                                st.info(row['ROADMAP_NOTE'], icon='🗓️')

        st.divider()
        st.markdown("#### Connector Coverage by Type")
        if not connectors_df.empty:
            active_df = connectors_df[connectors_df['STATUS'] == 'ACTIVE']
            c1, c2, c3 = st.columns(3)
            for col, stype, label, desc in [
                (c1, 'DATABASE', '🗄️ Databases', 'PostgreSQL, SQL Server (GA) · BigQuery, MySQL (PuPr)'),
                (c2, 'BI_TOOL', '📊 BI Tools', 'Tableau, Power BI (GA) · Looker (PuPr) · Sigma (GA)'),
                (c3, 'PIPELINE', '🔧 Pipelines', 'dbt Cloud (GA) · Fivetran, Dagster (PuPr)'),
            ]:
                count = len(active_df[active_df['SOURCE_TYPE'] == stype])
                col.markdown(f"""
                <div class="metric-card">
                    <div style="font-size:1.3rem;">{label}</div>
                    <div style="font-size:1.8rem;font-weight:700;color:#29B5E8;">{count} active</div>
                    <small style="color:#64748B;">{desc}</small>
                </div>
                """, unsafe_allow_html=True)

    # ── TAB 2: Universal Catalog ──────────────────────────────────────────────
    with tab_catalog:
        st.markdown("### Universal Catalog — Snowflake + External Metadata")

        col_search, col_type, col_src, col_sens = st.columns([3,1,1,1])
        with col_search:
            search_q = st.text_input("🔍 Search catalog", placeholder="e.g. customers, revenue, payroll…",
                                     label_visibility='collapsed')
        with col_type:
            type_filter = st.selectbox('Type', ['All','TABLE','VIEW','COLUMN','DASHBOARD','REPORT','MODEL'],
                                       label_visibility='collapsed')
        with col_src:
            sources = ['All'] + sorted({
                'PostgreSQL','Microsoft SQL Server','Tableau','Power BI','dbt Cloud','Snowflake'
            })
            src_filter = st.selectbox('Source', sources, label_visibility='collapsed')
        with col_sens:
            sens_filter = st.selectbox('Sensitivity', ['All','PUBLIC','INTERNAL','CONFIDENTIAL','RESTRICTED'],
                                       label_visibility='collapsed')

        catalog_results = get_unified_catalog(
            search_query=search_q,
            obj_type=type_filter if type_filter != 'All' else None,
            source=src_filter if src_filter != 'All' else None,
            sensitivity=sens_filter if sens_filter != 'All' else None,
        )

        if catalog_results.empty:
            st.info("No objects match your search, or the Horizon Context schema has not been deployed yet.")
        else:
            st.caption(f"{len(catalog_results)} objects found across all connected systems")

            def _sensitivity_badge(s):
                colors = {'PUBLIC':'#18794E','INTERNAL':'#0369A1',
                          'CONFIDENTIAL':'#9333EA','RESTRICTED':'#DC2626'}
                return f"<span style='background:{colors.get(s,'#64748B')}22;color:{colors.get(s,'#64748B')};padding:2px 7px;border-radius:10px;font-size:0.78rem;font-weight:600;'>{s or 'UNCLASSIFIED'}</span>"

            def _pop_bar(score):
                if pd.isna(score):
                    return '—'
                w = int(score)
                color = '#29B5E8' if score >= 80 else '#64748B' if score >= 40 else '#CBD5E1'
                return (f"<div style='display:flex;align-items:center;gap:4px;'>"
                        f"<div style='width:{w}px;max-width:80px;height:6px;border-radius:3px;"
                        f"background:{color};'></div><small>{score:.0f}</small></div>")

            for idx, row in catalog_results.head(50).iterrows():
                icon = row.get('CONNECTOR_ICON', '📦') or '📦'
                color = row.get('CONNECTOR_COLOR', '#64748B') or '#64748B'
                name = row.get('QUALIFIED_NAME', '')
                short_name = name.split('.')[-1] if '.' in name else name
                desc = row.get('DESCRIPTION') or ''
                desc_snippet = (desc[:90] + '…') if len(desc) > 90 else desc
                sensitivity = row.get('SENSITIVITY_CLASS')
                pii = row.get('IS_PII', False)
                gap = row.get('HAS_GOVERNANCE_GAP', False)

                st.markdown(f"""
                <div style="background:white;border-radius:10px;padding:0.75rem 1rem;
                            border:1px solid {'#FCA5A5' if gap else '#E2E8F0'};
                            border-left:4px solid {color};margin-bottom:0.4rem;">
                    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
                        <div>
                            <span style="font-size:1rem;">{icon}</span>
                            <strong>{short_name}</strong>
                            <span style="color:#94A3B8;font-size:0.8rem;margin-left:6px;">{row.get('OBJECT_TYPE','')}</span>
                            {"<span style='color:#DC2626;font-size:0.78rem;margin-left:8px;'>⚠ PII</span>" if pii else ''}
                            {"<span style='color:#F59E0B;font-size:0.78rem;margin-left:8px;'>⚠ gap</span>" if gap else ''}
                        </div>
                        <div style="display:flex;gap:8px;align-items:center;">
                            {_sensitivity_badge(sensitivity)}
                            <span style="color:#64748B;font-size:0.8rem;">{row.get('SOURCE_SYSTEM','')}</span>
                        </div>
                    </div>
                    <div style="color:#475569;font-size:0.83rem;margin-top:0.3rem;">
                        {desc_snippet if desc_snippet else '<em style="color:#94A3B8;">No description — see AI Governance tab to enrich</em>'}
                    </div>
                    <div style="display:flex;gap:1.5rem;margin-top:0.4rem;font-size:0.78rem;color:#64748B;">
                        <span>Popularity {_pop_bar(row.get('POPULARITY_SCORE'))}</span>
                        <span>👤 {int(row.get('USER_COUNT_30D') or 0)} users/mo</span>
                        <span>⬇ {int(row.get('DOWNSTREAM_BI_COUNT') or 0)} BI consumers</span>
                        {"<span>👑 " + str(row.get('OWNER_TEAM','Unassigned')) + "</span>" if row.get('OWNER_TEAM') else '<span style="color:#DC2626;">No owner</span>'}
                    </div>
                </div>
                """, unsafe_allow_html=True)

    # ── TAB 3: Cross-Platform Lineage ─────────────────────────────────────────
    with tab_lineage:
        st.markdown("### Cross-Platform Data Lineage")
        st.caption(
            "Full lineage spanning external sources → dbt pipeline → Snowflake RAW / CURATED / SEMANTIC → BI tools. "
            "Horizon alone tracks lineage only inside Snowflake — Horizon Context extends it across the entire stack."
        )

        lineage_df = get_lineage_full()

        col_a, col_b = st.columns([2, 1])
        with col_a:
            all_node_labels = {
                'pg-customers': 'PostgreSQL: customers',
                'pg-transactions': 'PostgreSQL: transactions',
                'sql-journals': 'SQL Server: journal_entries',
                'sql-headcount': 'SQL Server: headcount',
                'pg-employees': 'PostgreSQL: employees',
                'sf-curated-fact-rev': 'Snowflake: FACT_REVENUE',
                'sf-sem-revenue': 'Snowflake: REVENUE_SUMMARY (Semantic)',
                'tab-rev-dash': 'Tableau: Executive Revenue Dashboard',
                'tab-cust360': 'Tableau: Customer 360 View',
                'pbi-finance': 'Power BI: Finance Monthly Reporting',
                'sf-curated-dim-cust': 'Snowflake: DIM_CUSTOMER',
                'sf-curated-dim-emp': 'Snowflake: DIM_EMPLOYEE',
                'sf-sem-workforce': 'Snowflake: WORKFORCE_SUMMARY (Semantic)',
                'tab-hr': 'Tableau: HR Analytics',
            }
            selected_focal_label = st.selectbox(
                'Highlight lineage path for object',
                ['Show all paths'] + list(all_node_labels.values()),
                index=0,
            )
            focal_id = None
            if selected_focal_label != 'Show all paths':
                for nid, label in all_node_labels.items():
                    if label == selected_focal_label:
                        focal_id = nid
                        break

        with col_b:
            if focal_id:
                st.markdown(f"""
                <div style="background:#F0F9FF;border-radius:8px;padding:0.75rem;border-left:3px solid #29B5E8;">
                <strong>Impact of changing this asset:</strong><br>
                <small>Hover over nodes to see downstream consumers.<br>
                Blue = selected object · Faded = unrelated paths</small>
                </div>
                """, unsafe_allow_html=True)

        fig = _build_lineage_figure(lineage_df, focal_id)
        st.plotly_chart(fig, use_container_width=True)

        # Path narrative
        if not lineage_df.empty:
            st.markdown("#### Lineage Paths")
            path_labels = {
                'path-cust-360': ('Customer 360', '🐘 PostgreSQL.customers → 🔧 dbt stg_customers → ❄️ RAW.SALESFORCE.ACCOUNT → ❄️ CURATED.DIM_CUSTOMER → 📊 Tableau Customer 360 · 📈 Power BI Customer Report'),
                'path-revenue':  ('Revenue',      '🐘 PostgreSQL.transactions → 🔧 dbt stg_transactions → ❄️ RAW.SAP.VBAK → ❄️ CURATED.FACT_REVENUE → ❄️ SEMANTIC.REVENUE_SUMMARY → 📊 Tableau Revenue Dashboard'),
                'path-finance':  ('Finance GL',   '🪟 SQL Server.journal_entries → ❄️ RAW.ORACLE.GL_JE_HEADERS → ❄️ CURATED.FACT_JOURNAL_ENTRIES → 📈 Power BI Finance Monthly · 📊 Tableau Finance Close'),
                'path-workforce':('Workforce',    '🪟 SQL Server.headcount + 🐘 PostgreSQL.employees → ❄️ RAW.WORKDAY.WORKERS → ❄️ CURATED.DIM_EMPLOYEE → ❄️ SEMANTIC.WORKFORCE_SUMMARY → 📊 Tableau HR Analytics'),
            }
            for path_id, (path_name, path_str) in path_labels.items():
                path_rows = lineage_df[lineage_df['LINEAGE_PATH_ID'] == path_id] if not lineage_df.empty else pd.DataFrame()
                hop_count = len(path_rows)
                with st.expander(f"**{path_name}** — {hop_count or '?'} hops"):
                    st.markdown(path_str)
                    if not path_rows.empty:
                        for _, edge in path_rows.sort_values('HOP_NUMBER').iterrows():
                            conf = float(edge.get('CONFIDENCE_SCORE') or 1.0)
                            st.markdown(
                                f"&nbsp;&nbsp;Hop {int(edge['HOP_NUMBER'])}: "
                                f"`{edge.get('SOURCE_TABLE','?')}` → `{edge.get('TARGET_TABLE','?')}` "
                                f"[{edge.get('LINEAGE_TYPE','')}] "
                                f"confidence {conf:.0%}"
                            )

    # ── TAB 4: Usage Intelligence ─────────────────────────────────────────────
    with tab_usage:
        st.markdown("### Usage Intelligence")
        st.caption(
            "Popularity scoring combines Snowflake QUERY_HISTORY, BI tool view counts, and distinct user access patterns. "
            "Scores drive governance prioritization — high-score assets warrant faster policy coverage."
        )

        usage_df = get_usage_intelligence()
        trends_df = get_usage_trends()

        if usage_df.empty:
            st.info("Deploy the Horizon Context schema to see usage intelligence data.")
        else:
            c1, c2, c3, c4 = st.columns(4)
            platinum = len(usage_df[usage_df['POPULARITY_TIER'] == 'PLATINUM']) if not usage_df.empty else 0
            gold     = len(usage_df[usage_df['POPULARITY_TIER'] == 'GOLD']) if not usage_df.empty else 0
            orphans  = len(usage_df[usage_df['IS_ORPHANED'] == True]) if not usage_df.empty else 0
            total_bi = int(usage_df['TOTAL_BI_VIEWS_14D'].sum()) if not usage_df.empty else 0
            for col, val, label, sub in [
                (c1, platinum, 'Platinum Assets', 'Popularity score ≥ 80'),
                (c2, gold,     'Gold Assets',     'Popularity score 60–79'),
                (c3, orphans,  'Orphaned Assets', 'Zero downstream consumers'),
                (c4, total_bi, 'BI Views (14d)',  'Across Tableau + Power BI'),
            ]:
                col.markdown(f"""
                <div class="metric-card">
                    <div style="font-size:1.6rem;font-weight:700;color:#29B5E8;">{val:,}</div>
                    <strong>{label}</strong><br><small style="color:#64748B;">{sub}</small>
                </div>
                """, unsafe_allow_html=True)

            st.divider()
            left_col, right_col = st.columns([3, 2])

            with left_col:
                st.markdown("#### Top 15 Assets by Popularity")
                top15 = usage_df.head(15)
                for _, row in top15.iterrows():
                    icon = row.get('CONNECTOR_ICON', '📦') or '📦'
                    score = float(row.get('POPULARITY_SCORE') or 0)
                    color = row.get('CONNECTOR_COLOR', '#64748B') or '#64748B'
                    tier  = row.get('POPULARITY_TIER', '')
                    tier_badge = {'PLATINUM':'🥇','GOLD':'🥈','SILVER':'🥉','BRONZE':'🏅'}.get(tier,'')
                    table = row.get('QUALIFIED_NAME', '')
                    short = table.split('.')[-1] if '.' in table else table
                    sys_name = row.get('SOURCE_SYSTEM', '')
                    qcount = int(row.get('QUERY_COUNT_30D') or 0)
                    ucount = int(row.get('USER_COUNT_30D') or 0)
                    bi_count = int(row.get('DOWNSTREAM_BI_COUNT') or 0)
                    bar_w = int(score * 1.5)

                    st.markdown(f"""
                    <div style="display:flex;align-items:center;gap:10px;
                                padding:0.5rem 0.75rem;border-radius:8px;margin-bottom:3px;
                                background:white;border:1px solid #F1F5F9;">
                        <span>{icon}</span>
                        <div style="flex:1;min-width:0;">
                            <div style="font-weight:600;font-size:0.88rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">{short} {tier_badge}</div>
                            <div style="background:#E2E8F0;border-radius:3px;height:5px;margin-top:3px;">
                                <div style="width:{bar_w}px;max-width:100%;height:5px;border-radius:3px;background:{color};"></div>
                            </div>
                        </div>
                        <div style="text-align:right;font-size:0.78rem;color:#64748B;white-space:nowrap;">
                            <div><b>{score:.0f}</b> score</div>
                            <div>{qcount:,} qry · {ucount} users · {bi_count} BI</div>
                        </div>
                    </div>
                    """, unsafe_allow_html=True)

            with right_col:
                st.markdown("#### Orphaned Assets")
                st.caption("Zero downstream consumers in 90 days — candidates for deprecation")
                orphan_df = usage_df[usage_df['IS_ORPHANED'] == True]
                if orphan_df.empty:
                    st.success("No orphaned assets detected.")
                else:
                    for _, row in orphan_df.iterrows():
                        icon = row.get('CONNECTOR_ICON', '📦') or '📦'
                        table = row.get('QUALIFIED_NAME', '')
                        short = table.split('.')[-1] if '.' in table else table
                        qcount = int(row.get('QUERY_COUNT_30D') or 0)
                        owner = row.get('OWNER_EMAIL') or '⚠ No owner'
                        st.markdown(f"""
                        <div style="background:#FFF7ED;border-radius:8px;padding:0.5rem 0.75rem;
                                    border-left:3px solid #F59E0B;margin-bottom:0.4rem;font-size:0.85rem;">
                            {icon} <strong>{short}</strong><br>
                            {qcount} queries/mo · {owner}
                        </div>
                        """, unsafe_allow_html=True)

            # Trend chart
            if not trends_df.empty:
                st.divider()
                st.markdown("#### 14-Day Query Volume Trend (Top Assets)")
                try:
                    trends_df['STAT_DATE'] = pd.to_datetime(trends_df['STAT_DATE'])
                    pivot = trends_df.pivot_table(
                        index='STAT_DATE', columns='TABLE_NAME',
                        values='QUERY_COUNT', aggfunc='sum'
                    ).fillna(0)
                    trend_fig = go.Figure()
                    colors_cycle = ['#29B5E8','#11567F','#FF694A','#E97627','#18794E','#9333EA']
                    for i, col in enumerate(pivot.columns[:6]):
                        trend_fig.add_trace(go.Scatter(
                            x=pivot.index, y=pivot[col],
                            mode='lines+markers', name=col,
                            line=dict(color=colors_cycle[i % len(colors_cycle)], width=2),
                            marker=dict(size=5),
                        ))
                    trend_fig.update_layout(
                        height=280, margin=dict(l=10, r=10, t=30, b=10),
                        legend=dict(orientation='h', yanchor='top', y=-0.1),
                        plot_bgcolor='white', paper_bgcolor='white',
                        xaxis=dict(showgrid=True, gridcolor='#F1F5F9'),
                        yaxis=dict(showgrid=True, gridcolor='#F1F5F9', title='Queries / day'),
                    )
                    st.plotly_chart(trend_fig, use_container_width=True)
                except Exception:
                    pass

    # ── TAB 5: AI Governance ──────────────────────────────────────────────────
    with tab_ai:
        st.markdown("### AI Governance Enrichment")
        st.caption(
            "Select Star's metadata analysis + Cortex AI surfaces governance gaps and auto-generates "
            "descriptions, tag suggestions, owner assignments, and deprecation candidates."
        )

        recs_df = get_governance_recommendations()
        gaps_df = get_governance_gaps()

        # Gap summary
        if not gaps_df.empty:
            missing_desc  = int(gaps_df['MISSING_DESCRIPTION'].sum())
            missing_owner = int(gaps_df['MISSING_OWNER'].sum())
            missing_sens  = int(gaps_df['MISSING_SENSITIVITY'].sum())
            pii_gap       = int(gaps_df['UNDECLARED_PII'].sum())
            g1, g2, g3, g4 = st.columns(4)
            for gcol, gval, glabel, gcolor in [
                (g1, missing_desc,  'Missing Descriptions', '#E97627'),
                (g2, missing_owner, 'Missing Owners',       '#DC2626'),
                (g3, missing_sens,  'Missing Sensitivity',  '#9333EA'),
                (g4, pii_gap,       'Undeclared PII',       '#DC2626'),
            ]:
                gcol.markdown(f"""
                <div class="metric-card" style="border-left-color:{gcolor};">
                    <div style="font-size:1.6rem;font-weight:700;color:{gcolor};">{gval}</div>
                    <strong>{glabel}</strong>
                </div>
                """, unsafe_allow_html=True)

        st.divider()

        panel_recs, panel_cortex = st.columns([3, 2])

        with panel_recs:
            st.markdown("#### Open Governance Recommendations")
            if recs_df.empty:
                st.success("No open governance recommendations. Well governed!")
            else:
                PRIORITY_COLORS = {
                    'CRITICAL': ('#DC2626','#FFF1F2'),
                    'HIGH':     ('#EA580C','#FFF7ED'),
                    'MEDIUM':   ('#CA8A04','#FEFCE8'),
                    'LOW':      ('#16A34A','#F0FDF4'),
                }
                REC_ICONS = {
                    'APPLY_MASK': '🔒', 'ADD_TAG': '🏷️', 'ASSIGN_OWNER': '👤',
                    'ADD_DESCRIPTION': '📝', 'DEPRECATE': '🗑️',
                    'REVIEW_PII': '⚠️', 'CERTIFY': '✅',
                }
                for _, rec in recs_df.iterrows():
                    priority = rec.get('PRIORITY', 'MEDIUM')
                    p_color, p_bg = PRIORITY_COLORS.get(priority, ('#64748B','#F8FAFC'))
                    rec_icon = REC_ICONS.get(rec.get('RECOMMENDATION_TYPE',''), '💡')
                    rec_id = rec.get('REC_ID', '')
                    obj_icon = rec.get('CONNECTOR_ICON', '📦') or '📦'
                    obj_name = str(rec.get('QUALIFIED_NAME', '')).split('.')[-1]
                    reason_text = str(rec.get('REASON', ''))[:160] + '…' if len(str(rec.get('REASON',''))) > 160 else str(rec.get('REASON',''))
                    suggested = str(rec.get('SUGGESTED_VALUE', ''))[:120] if rec.get('SUGGESTED_VALUE') else None
                    conf = float(rec.get('AI_CONFIDENCE') or 0)

                    with st.expander(
                        f"{rec_icon} **{rec.get('RECOMMENDATION_TYPE','')}** on {obj_icon} `{obj_name}` "
                        f"— [{priority}]",
                        expanded=(priority == 'CRITICAL'),
                    ):
                        st.markdown(f"**Reason:** {reason_text}")
                        if suggested:
                            st.markdown(f"**Suggested action:** _{suggested}_")
                        st.progress(conf, text=f"AI confidence: {conf:.0%}")
                        col_apply, col_dismiss = st.columns(2)
                        with col_apply:
                            if st.button("✅ Accept", key=f"accept_{rec_id}", type="primary", use_container_width=True):
                                msg = hc_apply_recommendation(rec_id, get_current_role())
                                st.success(msg)
                                st.rerun()
                        with col_dismiss:
                            if st.button("✗ Dismiss", key=f"dismiss_{rec_id}", use_container_width=True):
                                hc_apply_recommendation(rec_id, 'DISMISSED')
                                st.rerun()

        with panel_cortex:
            st.markdown("#### Cortex AI Metadata Enrichment")
            st.caption("Generate business descriptions for ungoverned external catalog objects")

            if not gaps_df.empty:
                needs_desc = gaps_df[gaps_df['MISSING_DESCRIPTION'] == True]
                if not needs_desc.empty:
                    obj_options = needs_desc.apply(
                        lambda r: f"{r.get('CONNECTOR_ICON','📦')} {r['QUALIFIED_NAME'].split('.')[-1]} ({r.get('SOURCE_SYSTEM','')})",
                        axis=1
                    ).tolist()
                    selected_label = st.selectbox(
                        "Select ungoverned object to enrich",
                        obj_options,
                        label_visibility='visible',
                    )
                    selected_idx = obj_options.index(selected_label)
                    sel_row = needs_desc.iloc[selected_idx]

                    st.markdown(f"""
                    **Object:** `{sel_row['QUALIFIED_NAME']}`  
                    **Type:** {sel_row.get('OBJECT_TYPE','')} · **Risk Score:** {int(sel_row.get('GOVERNANCE_RISK_SCORE',0))}  
                    **Current description:** _None_
                    """)

                    if st.button("✨ Generate Description with Cortex", type="primary", use_container_width=True):
                        with st.spinner("Calling Cortex mistral-large2…"):
                            generated = hc_enrich_with_cortex(
                                object_id=sel_row['OBJECT_ID'],
                                table_name=sel_row['QUALIFIED_NAME'].split('.')[-1],
                                col_name=sel_row.get('COLUMN_NAME'),
                                source_system=sel_row.get('SOURCE_SYSTEM',''),
                                obj_type=sel_row.get('OBJECT_TYPE',''),
                            )
                        if generated and not generated.startswith('Cortex error'):
                            st.success("Description applied to catalog!")
                            st.markdown(f"""
                            <div style="background:#F0FDF4;border-radius:8px;padding:0.75rem;
                                        border-left:3px solid #18794E;">
                            <strong>AI-generated description:</strong><br>{generated}
                            </div>
                            """, unsafe_allow_html=True)
                        else:
                            st.error(generated or 'No description returned.')

            st.divider()
            st.markdown("#### How AI Enrichment Works")
            st.markdown("""
            1. Select Star crawls external objects and scores governance completeness
            2. Objects with missing descriptions, owners, or sensitivity tags are flagged
            3. Cortex `mistral-large2` generates context-aware descriptions from:
               - Column/table names and data types
               - Cross-system lineage context (what feeds it, who consumes it)
               - Existing dbt YAML docs and source system documentation
            4. Generated descriptions are written back to the Horizon Context catalog
            5. Snowflake object comments and Business Glossary entries are updated via `APPLY TAG`

            > **PrPr scope**: AI enrichment for external objects only.  
            > **PuPr scope**: Writeback to native Snowflake object comments and Business Glossary.
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
    elif page == "🌟 Horizon Context":
        render_horizon_context_page()
    elif page == "📋 Contracts":
        render_contracts_page()
    elif page == "ℹ️ About":
        render_about_page()

if __name__ == "__main__":
    main()
