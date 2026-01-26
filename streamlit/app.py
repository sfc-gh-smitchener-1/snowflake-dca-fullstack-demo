# ============================================================================
# SNOWFLAKE DATA CLOUD ARCHITECTURE - Streamlit Demo Application
# ============================================================================
# 
# A comprehensive dashboard demonstrating:
#   1. Cortex Analyst - Natural language queries on semantic views
#   2. Horizon Governance - Role-based access control demonstration
#   3. Data Marketplace - Data product discovery
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
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
    
    .stApp {
        background: linear-gradient(180deg, #FFFFFF 0%, #F0F9FF 100%);
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
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
    
    .metric-card.success { border-left-color: #18794E; }
    .metric-card.warning { border-left-color: #AD5700; }
    .metric-card.error { border-left-color: #CD2B31; }
    
    .chat-bubble {
        padding: 15px;
        border-radius: 12px;
        margin-bottom: 10px;
    }
    
    .user-bubble {
        background: #E3F5FC;
        border-left: 5px solid #29B5E8;
    }
    
    .assistant-bubble {
        background: #F1F5F9;
        border-left: 5px solid #6E56CF;
    }
    
    .role-badge {
        display: inline-block;
        padding: 5px 15px;
        border-radius: 20px;
        font-size: 0.8rem;
        font-weight: bold;
    }
    
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
</style>
""", unsafe_allow_html=True)

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
def get_dashboard_kpis():
    """Fetch dashboard KPIs"""
    session = get_session()
    try:
        df = session.sql("""
            SELECT 
                (SELECT COUNT(*) FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER WHERE _IS_CURRENT = TRUE) AS TOTAL_CUSTOMERS,
                (SELECT COUNT(*) FROM CURATED_DEV.DIMENSIONS.DIM_PRODUCT WHERE _IS_CURRENT = TRUE) AS TOTAL_PRODUCTS,
                (SELECT COUNT(*) FROM CURATED_DEV.FACTS.FACT_ORDERS WHERE _IS_CURRENT = TRUE) AS TOTAL_ORDERS,
                (SELECT COUNT(*) FROM CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE WHERE _IS_CURRENT = TRUE) AS TOTAL_EMPLOYEES
        """).to_pandas()
        return df
    except Exception as e:
        st.warning(f"Could not load KPIs: {str(e)}")
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_sales_by_region():
    """Get sales by region"""
    session = get_session()
    try:
        df = session.sql("""
            SELECT 
                REGION,
                COUNT(*) AS ORDER_COUNT,
                SUM(ORDER_TOTAL) AS TOTAL_REVENUE
            FROM CURATED_DEV.FACTS.FACT_ORDERS
            WHERE _IS_CURRENT = TRUE
            GROUP BY REGION
            ORDER BY TOTAL_REVENUE DESC
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def get_customer_segments():
    """Get customer segment distribution"""
    session = get_session()
    try:
        df = session.sql("""
            SELECT 
                CUSTOMER_TIER,
                COUNT(*) AS CUSTOMER_COUNT,
                ROUND(AVG(LIFETIME_VALUE), 2) AS AVG_LTV
            FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
            WHERE _IS_CURRENT = TRUE
            GROUP BY CUSTOMER_TIER
            ORDER BY CUSTOMER_COUNT DESC
        """).to_pandas()
        return df
    except:
        return pd.DataFrame()

def get_semantic_views():
    """Get available semantic views"""
    return [
        'SEM_DEV.SEM_SALES.SALES_ANALYTICS',
        'SEM_DEV.SEM_CUSTOMER.CUSTOMER_ANALYTICS',
        'SEM_DEV.SEM_OPERATIONS.OPERATIONS_METRICS',
        'SEM_DEV.SEM_HR.WORKFORCE_ANALYTICS'
    ]

def execute_cortex_query(prompt: str, semantic_view: str):
    """Execute Cortex Analyst query using CORTEX.COMPLETE fallback"""
    session = get_session()
    
    try:
        # Use CORTEX.COMPLETE to generate SQL
        escaped_prompt = prompt.replace("'", "''")
        escaped_view = semantic_view.replace("'", "''")
        
        result = session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                'llama3.1-70b',
                'Generate a Snowflake SQL query for this question. 
                 Use the semantic view: {escaped_view}
                 
                 Question: {escaped_prompt}
                 
                 Return ONLY the SQL query, no explanation.
                 Use standard SQL aggregations and GROUP BY.'
            ) AS response
        """).to_pandas()
        
        if not result.empty and result['RESPONSE'].iloc[0]:
            sql = result['RESPONSE'].iloc[0].strip()
            
            # Clean up the SQL
            if '```' in sql:
                parts = sql.split('```')
                for part in parts:
                    if 'SELECT' in part.upper():
                        sql = part.strip()
                        if sql.lower().startswith('sql'):
                            sql = sql[3:].strip()
                        break
            
            # Execute the generated SQL
            try:
                data_result = session.sql(sql).to_pandas()
                return sql, data_result, None
            except Exception as exec_error:
                return sql, None, f"SQL execution error: {str(exec_error)}"
        else:
            return None, None, "Could not generate SQL"
            
    except Exception as e:
        return None, None, f"Error: {str(e)}"

# ============================================================================
# ROLE DEFINITIONS
# ============================================================================

def get_available_roles():
    """Get list of roles for switching"""
    return [
        ("DATA_ADMIN", "🔧 Data Admin", "Full system access - all data visible"),
        ("DATA_STEWARD", "📋 Data Steward", "Governance access - monitors data quality"),
        ("ANALYST", "📊 Analyst", "Business analyst - semantic layer, masked PII"),
        ("MANAGER", "👔 Manager", "Manager access - partial PII visibility"),
        ("VIEWER", "👁️ Viewer", "Read-only - aggregates only"),
        ("AI_AGENT", "🤖 AI Agent", "AI workloads - pseudonymized data"),
    ]

def get_role_info(role: str) -> dict:
    """Get role access information"""
    role_info = {
        "DATA_ADMIN": {
            "icon": "🔧",
            "color": "#CD2B31",
            "access": "FULL ACCESS",
            "description": "Complete access to all data including PII",
            "pii_level": "Full"
        },
        "DATA_STEWARD": {
            "icon": "📋",
            "color": "#6E56CF",
            "access": "GOVERNANCE",
            "description": "Governance and quality monitoring access",
            "pii_level": "Masked"
        },
        "ANALYST": {
            "icon": "📊",
            "color": "#29B5E8",
            "access": "SEMANTIC LAYER",
            "description": "Business analytics with masked PII",
            "pii_level": "Masked"
        },
        "MANAGER": {
            "icon": "👔",
            "color": "#AD5700",
            "access": "DEPARTMENT SCOPE",
            "description": "Department-level access with partial PII",
            "pii_level": "Partial"
        },
        "VIEWER": {
            "icon": "👁️",
            "color": "#64748B",
            "access": "AGGREGATES ONLY",
            "description": "Read-only access to aggregated data",
            "pii_level": "None"
        },
        "AI_AGENT": {
            "icon": "🤖",
            "color": "#18794E",
            "access": "AI-SAFE DATA",
            "description": "Pseudonymized data for AI/ML workloads",
            "pii_level": "Pseudonymized"
        }
    }
    return role_info.get(role, {
        "icon": "👤",
        "color": "#64748B",
        "access": "UNKNOWN",
        "description": "Unknown role",
        "pii_level": "Unknown"
    })

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
            <p style="color: #29B5E8; font-size: 0.85rem;">Full Stack Demo</p>
        </div>
        """, unsafe_allow_html=True)
        
        st.divider()
        
        # =====================================================================
        # ROLE SWITCHER
        # =====================================================================
        st.markdown("### 🔐 Role Switcher")
        st.caption("Switch roles to see RBAC in action")
        
        current_role = get_current_role()
        available_roles = get_available_roles()
        
        role_options = [f"{r[1]}" for r in available_roles]
        role_names = [r[0] for r in available_roles]
        
        try:
            current_idx = role_names.index(current_role)
        except ValueError:
            current_idx = 0
        
        selected_display = st.selectbox(
            "Select Role",
            role_options,
            index=current_idx,
            key="role_selector",
            label_visibility="collapsed"
        )
        
        selected_idx = role_options.index(selected_display)
        selected_role = role_names[selected_idx]
        
        role_info = get_role_info(selected_role)
        st.markdown(f"""
        <div style="background: rgba(41, 181, 232, 0.2); padding: 8px 12px; border-radius: 8px;">
            <small style="color: #E3F5FC;">{role_info['description']}</small>
        </div>
        """, unsafe_allow_html=True)
        
        if selected_role != current_role:
            if st.button("🔄 Switch Role", use_container_width=True):
                if switch_role(selected_role):
                    st.success(f"Switched to {selected_role}")
                    st.cache_data.clear()
                    st.rerun()
        else:
            st.markdown('<div style="text-align: center;"><span style="color: #18794E;">✓ Active</span></div>', 
                       unsafe_allow_html=True)
        
        st.divider()
        
        # Navigation
        page = st.radio(
            "Navigation",
            ["🏠 Dashboard", "🤖 Cortex Analyst", "🔮 Governance Demo", "🏪 Data Products", "ℹ️ About"],
            label_visibility="collapsed"
        )
        
        st.divider()
        
        # Quick stats
        st.markdown("### 📈 Quick Stats")
        kpis = get_dashboard_kpis()
        if not kpis.empty:
            col1, col2 = st.columns(2)
            with col1:
                if 'TOTAL_CUSTOMERS' in kpis.columns:
                    st.metric("Customers", f"{int(kpis['TOTAL_CUSTOMERS'].iloc[0]):,}")
                if 'TOTAL_ORDERS' in kpis.columns:
                    st.metric("Orders", f"{int(kpis['TOTAL_ORDERS'].iloc[0]):,}")
            with col2:
                if 'TOTAL_PRODUCTS' in kpis.columns:
                    st.metric("Products", f"{int(kpis['TOTAL_PRODUCTS'].iloc[0]):,}")
                if 'TOTAL_EMPLOYEES' in kpis.columns:
                    st.metric("Employees", f"{int(kpis['TOTAL_EMPLOYEES'].iloc[0]):,}")
        
        return page

# ============================================================================
# PAGE: DASHBOARD
# ============================================================================

def render_dashboard():
    """Render main dashboard"""
    st.markdown("""
    <div class="main-header">
        <h1>🏠 Executive Dashboard</h1>
        <p>Real-time business metrics powered by Dynamic Tables</p>
    </div>
    """, unsafe_allow_html=True)
    
    kpis = get_dashboard_kpis()
    
    # KPI Cards
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        val = kpis['TOTAL_CUSTOMERS'].iloc[0] if not kpis.empty and 'TOTAL_CUSTOMERS' in kpis.columns else 0
        st.markdown(f"""
        <div class="metric-card success">
            <strong>Total Customers</strong>
            <h2 style="margin: 0.5rem 0 0 0; font-size: 1.75rem;">{int(val):,}</h2>
        </div>
        """, unsafe_allow_html=True)
    
    with col2:
        val = kpis['TOTAL_ORDERS'].iloc[0] if not kpis.empty and 'TOTAL_ORDERS' in kpis.columns else 0
        st.markdown(f"""
        <div class="metric-card">
            <strong>Total Orders</strong>
            <h2 style="margin: 0.5rem 0 0 0; font-size: 1.75rem;">{int(val):,}</h2>
        </div>
        """, unsafe_allow_html=True)
    
    with col3:
        val = kpis['TOTAL_PRODUCTS'].iloc[0] if not kpis.empty and 'TOTAL_PRODUCTS' in kpis.columns else 0
        st.markdown(f"""
        <div class="metric-card">
            <strong>Products</strong>
            <h2 style="margin: 0.5rem 0 0 0; font-size: 1.75rem;">{int(val):,}</h2>
        </div>
        """, unsafe_allow_html=True)
    
    with col4:
        val = kpis['TOTAL_EMPLOYEES'].iloc[0] if not kpis.empty and 'TOTAL_EMPLOYEES' in kpis.columns else 0
        st.markdown(f"""
        <div class="metric-card">
            <strong>Employees</strong>
            <h2 style="margin: 0.5rem 0 0 0; font-size: 1.75rem;">{int(val):,}</h2>
        </div>
        """, unsafe_allow_html=True)
    
    st.divider()
    
    # Charts
    col1, col2 = st.columns(2)
    
    with col1:
        st.markdown("### 📊 Sales by Region")
        sales_data = get_sales_by_region()
        if not sales_data.empty:
            st.bar_chart(sales_data.set_index('REGION')['TOTAL_REVENUE'])
        else:
            st.info("No sales data available")
    
    with col2:
        st.markdown("### 👥 Customer Segments")
        segment_data = get_customer_segments()
        if not segment_data.empty:
            st.bar_chart(segment_data.set_index('CUSTOMER_TIER')['CUSTOMER_COUNT'])
        else:
            st.info("No segment data available")

# ============================================================================
# PAGE: CORTEX ANALYST
# ============================================================================

def render_cortex_page():
    """Render Cortex Analyst chat interface"""
    st.markdown("""
    <div class="main-header">
        <h1>🤖 Cortex Analyst</h1>
        <p>Ask questions in natural language - powered by Snowflake Cortex</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Semantic view selector
    col1, col2 = st.columns([3, 1])
    with col1:
        selected_view = st.selectbox(
            "Select Semantic View",
            get_semantic_views()
        )
    with col2:
        st.write("")
        if st.button("🔄 Clear Chat"):
            st.session_state.chat_history = []
            st.rerun()
    
    # Initialize chat history
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []
    
    # Sample questions
    if not st.session_state.chat_history:
        st.markdown("### 💡 Sample Questions")
        
        sample_questions = [
            "What are total orders by region?",
            "Show me customer count by segment",
            "What is the average order value?",
            "Which sales channel has the most orders?"
        ]
        
        cols = st.columns(2)
        for i, q in enumerate(sample_questions):
            with cols[i % 2]:
                if st.button(f"💬 {q}", key=f"sample_{i}", use_container_width=True):
                    st.session_state.pending_question = q
                    st.rerun()
    
    st.divider()
    
    # Display chat history
    for chat in st.session_state.chat_history:
        if chat["role"] == "user":
            st.markdown(f"""
            <div class="chat-bubble user-bubble">
                <strong>👤 You</strong><br>{chat["content"]}
            </div>
            """, unsafe_allow_html=True)
        else:
            st.markdown(f"""
            <div class="chat-bubble assistant-bubble">
                <strong>🤖 Cortex</strong><br>{chat["content"]}
            </div>
            """, unsafe_allow_html=True)
            if "sql" in chat and chat["sql"]:
                with st.expander("View SQL", expanded=False):
                    st.code(chat["sql"], language="sql")
            if "data" in chat and chat["data"] is not None and not chat["data"].empty:
                st.dataframe(chat["data"], use_container_width=True)
    
    # Handle pending question from sample buttons
    if "pending_question" in st.session_state:
        question = st.session_state.pending_question
        del st.session_state.pending_question
        
        st.session_state.chat_history.append({"role": "user", "content": question})
        
        sql, data, error = execute_cortex_query(question, selected_view)
        
        if error:
            st.session_state.chat_history.append({
                "role": "assistant",
                "content": f"❌ {error}"
            })
        else:
            st.session_state.chat_history.append({
                "role": "assistant",
                "content": "Here are the results:",
                "sql": sql,
                "data": data
            })
        st.rerun()
    
    # Input
    col1, col2 = st.columns([5, 1])
    with col1:
        question = st.text_input(
            "Ask a question",
            placeholder="Ask about your data...",
            label_visibility="collapsed"
        )
    with col2:
        ask_clicked = st.button("🚀 Ask", use_container_width=True)
    
    if ask_clicked and question:
        st.session_state.chat_history.append({"role": "user", "content": question})
        
        sql, data, error = execute_cortex_query(question, selected_view)
        
        if error:
            st.session_state.chat_history.append({
                "role": "assistant",
                "content": f"❌ {error}"
            })
        else:
            st.session_state.chat_history.append({
                "role": "assistant",
                "content": "Here are the results:",
                "sql": sql,
                "data": data
            })
        st.rerun()

# ============================================================================
# PAGE: GOVERNANCE DEMO
# ============================================================================

def render_governance_page():
    """Render governance demonstration"""
    st.markdown("""
    <div class="main-header">
        <h1>🔮 Horizon Governance Demo</h1>
        <p>See how data access changes based on your role</p>
    </div>
    """, unsafe_allow_html=True)
    
    current_role = get_current_role()
    role_info = get_role_info(current_role)
    
    # Current role indicator
    st.markdown(f"""
    <div style="background: linear-gradient(135deg, {role_info['color']}22 0%, {role_info['color']}11 100%);
                border-left: 4px solid {role_info['color']};
                padding: 1rem 1.5rem;
                border-radius: 8px;
                margin-bottom: 1.5rem;">
        <div style="display: flex; align-items: center; gap: 12px;">
            <span style="font-size: 2rem;">{role_info['icon']}</span>
            <div>
                <div style="font-weight: 700; color: {role_info['color']};">
                    {current_role} - {role_info['access']}
                </div>
                <div style="color: #64748B;">PII Level: {role_info['pii_level']}</div>
            </div>
        </div>
    </div>
    """, unsafe_allow_html=True)
    
    # Access comparison
    st.markdown("### 📋 Role Access Matrix")
    
    st.markdown("""
    | Role | PII Access | Email | Salary | SSN | Scope |
    |------|-----------|-------|--------|-----|-------|
    | 🔧 DATA_ADMIN | Full | ✓ Full | ✓ Full | ✓ Full | All |
    | 📋 DATA_STEWARD | Masked | Partial | Hidden | Hidden | All |
    | 📊 ANALYST | Masked | Partial | Hidden | Hidden | Assigned |
    | 👔 MANAGER | Partial | ✓ Full | Rounded | Last 4 | Department |
    | 👁️ VIEWER | None | Hidden | Hidden | Hidden | Aggregates |
    | 🤖 AI_AGENT | Pseudonymized | Hashed | Hidden | Hidden | Aggregates |
    """)
    
    st.divider()
    
    # Query data with current role
    st.markdown("### 🔍 Sample Data Query")
    st.caption("⚠️ Data visibility changes based on your role. Switch roles in the sidebar to see the difference.")
    
    session = get_session()
    
    try:
        if current_role in ['DATA_ADMIN', 'PII_VIEWER']:
            df = session.sql("""
                SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE,
                       CUSTOMER_TIER, LIFETIME_VALUE, REGION
                FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
                WHERE _IS_CURRENT = TRUE
                LIMIT 10
            """).to_pandas()
            st.success("🔓 Full PII Access - All fields visible")
        else:
            df = session.sql("""
                SELECT CUSTOMER_ID, DISPLAY_NAME, CUSTOMER_TIER, 
                       LIFETIME_VALUE, REGION, CUSTOMER_HEALTH
                FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
                WHERE _IS_CURRENT = TRUE
                LIMIT 10
            """).to_pandas()
            st.warning("🔒 Masked Access - PII fields hidden or masked")
        
        if not df.empty:
            st.dataframe(df, use_container_width=True)
        else:
            st.info("No data available for this role")
            
    except Exception as e:
        st.error(f"Query error: {str(e)}")

# ============================================================================
# PAGE: DATA PRODUCTS
# ============================================================================

def render_marketplace_page():
    """Render data products/marketplace page"""
    st.markdown("""
    <div class="main-header">
        <h1>🏪 Data Products</h1>
        <p>Self-service data products for internal consumption</p>
    </div>
    """, unsafe_allow_html=True)
    
    # Product cards
    products = [
        {
            "id": "DP-SALES-001",
            "name": "Sales Performance Metrics",
            "domain": "Sales",
            "description": "Aggregated monthly/quarterly sales metrics by region and channel",
            "access": ["ANALYST", "MANAGER", "VIEWER", "AI_AGENT"]
        },
        {
            "id": "DP-CUST-001",
            "name": "Customer Segments Summary",
            "domain": "Customer",
            "description": "Customer distribution and value metrics by segment and tier",
            "access": ["ANALYST", "MANAGER", "AI_AGENT"]
        },
        {
            "id": "DP-GEO-001",
            "name": "Regional Business Summary",
            "domain": "Operations",
            "description": "Combined customer and sales metrics by geographic region",
            "access": ["ANALYST", "MANAGER", "VIEWER"]
        },
        {
            "id": "DP-PROD-001",
            "name": "Product Performance",
            "domain": "Product",
            "description": "Product catalog metrics by category and brand",
            "access": ["ANALYST", "MANAGER", "AI_AGENT"]
        }
    ]
    
    current_role = get_current_role()
    
    cols = st.columns(2)
    for i, product in enumerate(products):
        with cols[i % 2]:
            has_access = current_role in product["access"] or current_role in ["DATA_ADMIN", "DATA_STEWARD"]
            
            st.markdown(f"""
            <div style="background: white; padding: 1.5rem; border-radius: 12px; 
                        border: 1px solid {'#29B5E8' if has_access else '#E2E8F0'};
                        margin-bottom: 1rem;
                        opacity: {1 if has_access else 0.6};">
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <div>
                        <h4 style="margin: 0; color: #0F172A;">{product['name']}</h4>
                        <span style="background: #E3F5FC; color: #11567F; padding: 2px 8px; 
                                     border-radius: 4px; font-size: 0.75rem;">{product['domain']}</span>
                    </div>
                    <span style="color: {'#18794E' if has_access else '#CD2B31'};">
                        {'✓ Access' if has_access else '🔒 Locked'}
                    </span>
                </div>
                <p style="color: #64748B; margin: 0.75rem 0; font-size: 0.9rem;">{product['description']}</p>
                <small style="color: #94A3B8;">ID: {product['id']}</small>
            </div>
            """, unsafe_allow_html=True)

# ============================================================================
# PAGE: ABOUT
# ============================================================================

def render_about_page():
    """Render about page"""
    st.markdown("""
    <div class="main-header">
        <h1>ℹ️ About This Demo</h1>
        <p>Snowflake Data Cloud Architecture - Full Stack Demo</p>
    </div>
    """, unsafe_allow_html=True)
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.markdown("""
        ### 🔮 Snowflake Horizon
        
        Enterprise governance with:
        - **Object Tagging** — Classification, PII, AI eligibility
        - **Dynamic Masking** — Role-based data protection
        - **Row Access** — Context-aware filtering
        - **Audit Trail** — Complete access history
        """)
        
        st.markdown("""
        ### 🏗️ Architecture
        
        - **RAW Layer** — SCD Type 2 history
        - **CURATED Layer** — Dynamic Tables
        - **SEMANTIC Layer** — Native Semantic Views
        - **Marketplace** — Data Products
        """)
    
    with col2:
        st.markdown("""
        ### 🤖 Snowflake Cortex
        
        AI capabilities:
        - **Cortex Analyst** — Natural language queries
        - **Semantic Views** — Pre-defined metrics
        - **LLM Functions** — Text generation
        """)
        
        st.markdown("""
        ### 📊 Sample Data
        
        - Customers, Orders, Products
        - Employees, Departments
        - Realistic, diverse data via Faker
        """)

# ============================================================================
# MAIN
# ============================================================================

def main():
    """Main application entry point"""
    page = render_sidebar()
    
    if page == "🏠 Dashboard":
        render_dashboard()
    elif page == "🤖 Cortex Analyst":
        render_cortex_page()
    elif page == "🔮 Governance Demo":
        render_governance_page()
    elif page == "🏪 Data Products":
        render_marketplace_page()
    elif page == "ℹ️ About":
        render_about_page()

if __name__ == "__main__":
    main()
