"""
United Rentals Fleet Finder — Streamlit in Snowflake (SiS)

Interactive fleet management demo with:
  - Page 1: Fleet Finder Map — find equipment by location, category, and radius
  - Page 2: Cortex Analyst — natural language fleet intelligence queries
  - RBAC Demo — role switcher showing graduated data access

Runs in Streamlit in Snowflake using only native packages:
  streamlit, pandas, snowflake.snowpark
"""

import streamlit as st
import pandas as pd
import json
from snowflake.snowpark.context import get_active_session

# ============================================================================
# SESSION AND CONFIG
# ============================================================================

st.set_page_config(page_title="UR Fleet Finder", page_icon="🏗️", layout="wide")

def get_session():
    return get_active_session()

# UR-specific roles for RBAC demo
UR_ROLES = {
    "UR_FLEET_MANAGER": {
        "label": "Fleet Manager",
        "desc": "Full fleet visibility — all branches, all regions, all pricing",
        "color": "#2196F3",
        "regions": ["NORTHEAST", "SOUTHEAST", "MIDWEST", "SOUTHWEST", "WEST"],
        "mask_pii": False,
        "show_rates": True,
    },
    "UR_REGIONAL_DIRECTOR": {
        "label": "Regional Director (SW)",
        "desc": "Southwest region only — full pricing",
        "color": "#4CAF50",
        "regions": ["SOUTHWEST"],
        "mask_pii": False,
        "show_rates": True,
    },
    "UR_BRANCH_MANAGER": {
        "label": "Branch Manager (Dallas #1)",
        "desc": "Single branch — Dallas #1 only",
        "color": "#FF9800",
        "regions": ["SOUTHWEST"],
        "branch_filter": "BR-01024",
        "mask_pii": False,
        "show_rates": True,
    },
    "UR_CORPORATE_ANALYST": {
        "label": "Corporate Analyst",
        "desc": "All regions — PII masked, pricing visible",
        "color": "#9C27B0",
        "regions": ["NORTHEAST", "SOUTHEAST", "MIDWEST", "SOUTHWEST", "WEST"],
        "mask_pii": True,
        "show_rates": True,
    },
    "UR_EXTERNAL_PARTNER": {
        "label": "External Partner",
        "desc": "Southwest only — no PII, no pricing",
        "color": "#F44336",
        "regions": ["SOUTHWEST"],
        "mask_pii": True,
        "show_rates": False,
    },
}

# Approximate coordinates for search locations
SEARCH_LOCATIONS = {
    "Dallas, TX": (32.7767, -96.7970),
    "Houston, TX": (29.7604, -95.3698),
    "Phoenix, AZ": (33.4484, -112.0740),
    "Chicago, IL": (41.8781, -87.6298),
    "Atlanta, GA": (33.7490, -84.3880),
    "Los Angeles, CA": (34.0522, -118.2437),
    "New York, NY": (40.7128, -74.0060),
    "Denver, CO": (39.7392, -104.9903),
    "Miami, FL": (25.7617, -80.1918),
    "Seattle, WA": (47.6062, -122.3321),
}

MILES_TO_METERS = 1609.344

# ============================================================================
# ROLE MANAGEMENT
# ============================================================================

def get_current_role() -> str:
    if "ur_role" in st.session_state:
        return st.session_state.ur_role
    return "UR_FLEET_MANAGER"

def get_role_config() -> dict:
    return UR_ROLES.get(get_current_role(), UR_ROLES["UR_FLEET_MANAGER"])

# ============================================================================
# DATA FUNCTIONS
# ============================================================================

def get_fleet_data(role_config: dict, category: str = None,
                   status: str = None) -> pd.DataFrame:
    """Query fleet data with role-based filtering (application-level RBAC demo)."""
    session = get_session()
    regions = role_config["regions"]
    region_list = ",".join([f"'{r}'" for r in regions])

    where_clauses = [f"REGION IN ({region_list})"]
    if role_config.get("branch_filter"):
        where_clauses.append(f"BRANCH_ID = '{role_config['branch_filter']}'")
    if category and category != "All":
        where_clauses.append(f"CATEGORY = '{category}'")
    if status and status != "All":
        where_clauses.append(f"STATUS = '{status}'")

    where = " AND ".join(where_clauses)

    # Select columns based on role permissions
    rate_cols = """
        DAILY_RATE, WEEKLY_RATE, MONTHLY_RATE,
    """ if role_config["show_rates"] else ""

    pii_cols = "BRANCH_MANAGER," if not role_config["mask_pii"] else ""

    sql = f"""
        SELECT
            EQUIPMENT_ID, MAKE, MODEL, CATEGORY, DESCRIPTION,
            STATUS, STATUS_LABEL, CONDITION, YEAR_MANUFACTURED,
            EQUIPMENT_LAT, EQUIPMENT_LON,
            {rate_cols}
            HOUR_METER_READING,
            BRANCH_ID, BRANCH_NAME, BRANCH_CITY, BRANCH_STATE,
            BRANCH_LAT, BRANCH_LON, REGION,
            {pii_cols}
            FUEL_LEVEL_PCT, FAULT_CODE
        FROM CURATED_DEV.UNITED_RENTALS.FLEET_AVAILABILITY
        WHERE {where}
        ORDER BY CATEGORY, MAKE, MODEL
    """
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query error: {e}")
        return pd.DataFrame()


def get_branch_summary(role_config: dict) -> pd.DataFrame:
    """Get branch-level equipment counts for map markers."""
    session = get_session()
    regions = role_config["regions"]
    region_list = ",".join([f"'{r}'" for r in regions])

    branch_filter = ""
    if role_config.get("branch_filter"):
        branch_filter = f"AND e.BRANCH_ID = '{role_config['branch_filter']}'"

    sql = f"""
        SELECT
            b.BRANCH_ID, b.BRANCH_NAME, b.CITY, b.STATE,
            b.LATITUDE, b.LONGITUDE, b.REGION,
            COUNT(e.EQUIPMENT_ID) AS TOTAL_EQUIPMENT,
            COUNT_IF(e.STATUS = 'AVAILABLE') AS AVAILABLE,
            COUNT_IF(e.STATUS = 'RENTED') AS RENTED,
            COUNT_IF(e.STATUS = 'MAINTENANCE') AS IN_MAINTENANCE
        FROM CURATED_DEV.UNITED_RENTALS.DIM_BRANCH b
        LEFT JOIN CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT e
            ON b.BRANCH_ID = e.BRANCH_ID
        WHERE b.REGION IN ({region_list})
            {branch_filter}
        GROUP BY b.BRANCH_ID, b.BRANCH_NAME, b.CITY, b.STATE,
                 b.LATITUDE, b.LONGITUDE, b.REGION
        ORDER BY TOTAL_EQUIPMENT DESC
    """
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query error: {e}")
        return pd.DataFrame()


def search_nearby_equipment(lat: float, lon: float, radius_miles: float,
                            category: str, role_config: dict) -> pd.DataFrame:
    """Find available equipment within radius using ST_DISTANCE."""
    session = get_session()
    radius_meters = radius_miles * MILES_TO_METERS
    regions = role_config["regions"]
    region_list = ",".join([f"'{r}'" for r in regions])

    cat_filter = f"AND CATEGORY = '{category}'" if category and category != "All" else ""
    branch_filter = f"AND BRANCH_ID = '{role_config['branch_filter']}'" if role_config.get("branch_filter") else ""

    rate_cols = "DAILY_RATE, WEEKLY_RATE, MONTHLY_RATE," if role_config["show_rates"] else ""

    sql = f"""
        SELECT
            EQUIPMENT_ID, MAKE, MODEL, CATEGORY, DESCRIPTION,
            STATUS, CONDITION,
            EQUIPMENT_LAT, EQUIPMENT_LON,
            {rate_cols}
            BRANCH_NAME, BRANCH_CITY, BRANCH_STATE, REGION,
            ROUND(ST_DISTANCE(
                EQUIPMENT_LOCATION,
                ST_MAKEPOINT({lon}, {lat})
            ) / {MILES_TO_METERS}, 1) AS DISTANCE_MILES
        FROM CURATED_DEV.UNITED_RENTALS.FLEET_AVAILABILITY
        WHERE ST_DISTANCE(
                EQUIPMENT_LOCATION,
                ST_MAKEPOINT({lon}, {lat})
              ) <= {radius_meters}
          AND STATUS = 'AVAILABLE'
          AND REGION IN ({region_list})
          {cat_filter}
          {branch_filter}
        ORDER BY DISTANCE_MILES ASC
        LIMIT 500
    """
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query error: {e}")
        return pd.DataFrame()


# ============================================================================
# CORTEX ANALYST
# ============================================================================

def call_cortex_analyst(prompt: str, semantic_view: str):
    """Call Cortex Analyst API for natural language to SQL."""
    session = get_session()
    try:
        rest = session._conn._rest
        response = rest.request(
            url="/api/v2/cortex/analyst/message",
            method="POST",
            body={
                "messages": [
                    {"role": "user", "content": [{"type": "text", "text": prompt}]}
                ],
                "semantic_view": semantic_view,
            },
            headers={"Content-Type": "application/json"},
        )
        if response and "message" in response:
            return response, None
        return None, "Empty response from Cortex Analyst"
    except Exception as e:
        return None, str(e)


def parse_analyst_response(response: dict):
    """Extract SQL and text from Cortex Analyst response."""
    sql = None
    text_parts = []
    if response and "message" in response:
        content = response["message"].get("content", [])
        for item in content:
            if item.get("type") == "sql":
                sql = item.get("statement", "")
            elif item.get("type") == "text":
                text_parts.append(item.get("text", ""))
    return sql, "\n".join(text_parts)


# ============================================================================
# SIDEBAR
# ============================================================================

def render_sidebar():
    with st.sidebar:
        st.title("UR Fleet Finder")
        st.caption("United Rentals DCA Demo")
        st.divider()

        # Role Switcher
        st.subheader("RBAC Demo")
        current_role = get_current_role()
        role_keys = list(UR_ROLES.keys())
        current_idx = role_keys.index(current_role) if current_role in role_keys else 0

        selected = st.selectbox(
            "Active Role",
            role_keys,
            index=current_idx,
            format_func=lambda r: UR_ROLES[r]["label"],
        )
        if selected != current_role:
            st.session_state.ur_role = selected
            st.rerun()

        role_cfg = get_role_config()
        st.markdown(f"**{role_cfg['desc']}**")

        # Access badge
        badges = []
        badges.append(f"Regions: {', '.join(role_cfg['regions'])}")
        if role_cfg.get("branch_filter"):
            badges.append(f"Branch: {role_cfg['branch_filter']}")
        badges.append(f"PII: {'Masked' if role_cfg['mask_pii'] else 'Visible'}")
        badges.append(f"Pricing: {'Hidden' if not role_cfg['show_rates'] else 'Visible'}")
        for b in badges:
            st.caption(f"  {b}")

        st.divider()

        # Navigation
        st.subheader("Navigation")
        page = st.radio("Page", ["Fleet Finder", "Cortex Analyst"], label_visibility="collapsed")
        return page


# ============================================================================
# PAGE 1: FLEET FINDER MAP
# ============================================================================

def render_fleet_finder():
    role_config = get_role_config()
    st.header("Fleet Finder")
    st.caption("Find available equipment by location, category, and proximity")

    # Search controls
    col1, col2, col3, col4 = st.columns([2, 1, 1, 1])
    with col1:
        location = st.selectbox("Search Near", list(SEARCH_LOCATIONS.keys()))
    with col2:
        radius = st.slider("Radius (miles)", 10, 200, 50)
    with col3:
        categories = ["All", "AERIAL", "EARTHMOVING", "MATERIAL_HANDLING",
                      "GENERAL_TOOLS", "POWER_AND_HVAC", "TRENCH_SAFETY"]
        category = st.selectbox("Category", categories)
    with col4:
        st.write("")  # spacer
        search_clicked = st.button("Search", type="primary", use_container_width=True)

    search_lat, search_lon = SEARCH_LOCATIONS[location]

    # Metrics row
    branch_df = get_branch_summary(role_config)
    fleet_df = get_fleet_data(role_config)

    if not fleet_df.empty:
        m1, m2, m3, m4, m5 = st.columns(5)
        m1.metric("Branches", len(branch_df) if not branch_df.empty else 0)
        m2.metric("Total Equipment", len(fleet_df))
        m3.metric("Available", len(fleet_df[fleet_df["STATUS"] == "AVAILABLE"]))
        m4.metric("On Rent", len(fleet_df[fleet_df["STATUS"] == "RENTED"]))
        m5.metric("In Maintenance", len(fleet_df[fleet_df["STATUS"] == "MAINTENANCE"]))

    # Map and results
    if search_clicked or "search_results" not in st.session_state:
        results = search_nearby_equipment(search_lat, search_lon, radius, category, role_config)
        st.session_state.search_results = results
        st.session_state.search_location = (search_lat, search_lon)
        st.session_state.search_radius = radius
    else:
        results = st.session_state.get("search_results", pd.DataFrame())

    # Map display
    map_tab, table_tab = st.tabs(["Map View", "Table View"])

    with map_tab:
        if not results.empty:
            st.success(f"Found **{len(results)}** available equipment within **{radius} miles** of {location}")

            # Build map data — equipment points
            map_data = results.rename(columns={
                "EQUIPMENT_LAT": "latitude",
                "EQUIPMENT_LON": "longitude",
            })

            # Show the map with st.map (available in SiS)
            st.map(map_data[["latitude", "longitude"]], zoom=7)
        elif search_clicked:
            st.warning(f"No available equipment found within {radius} miles of {location} for the selected filters.")
        else:
            st.info("Click **Search** to find available equipment near a location.")

        # Branch summary below map
        if not branch_df.empty:
            with st.expander("Branch Summary", expanded=False):
                st.dataframe(
                    branch_df[["BRANCH_NAME", "CITY", "STATE", "REGION",
                               "TOTAL_EQUIPMENT", "AVAILABLE", "RENTED", "IN_MAINTENANCE"]],
                    use_container_width=True,
                    hide_index=True,
                )

    with table_tab:
        if not results.empty:
            display_cols = ["EQUIPMENT_ID", "MAKE", "MODEL", "CATEGORY", "DESCRIPTION",
                           "CONDITION", "BRANCH_NAME", "BRANCH_CITY", "REGION", "DISTANCE_MILES"]
            if role_config["show_rates"]:
                display_cols.extend(["DAILY_RATE", "WEEKLY_RATE", "MONTHLY_RATE"])

            available_cols = [c for c in display_cols if c in results.columns]
            st.dataframe(
                results[available_cols],
                use_container_width=True,
                hide_index=True,
                column_config={
                    "DAILY_RATE": st.column_config.NumberColumn("Daily Rate", format="$%.2f"),
                    "WEEKLY_RATE": st.column_config.NumberColumn("Weekly Rate", format="$%.2f"),
                    "MONTHLY_RATE": st.column_config.NumberColumn("Monthly Rate", format="$%.2f"),
                    "DISTANCE_MILES": st.column_config.NumberColumn("Distance (mi)", format="%.1f"),
                },
            )
        else:
            st.info("Search results will appear here.")


# ============================================================================
# PAGE 2: CORTEX ANALYST
# ============================================================================

def render_cortex_page():
    role_config = get_role_config()
    st.header("Fleet Intelligence — Cortex Analyst")
    st.caption("Ask natural language questions about fleet, rentals, and operations")

    # Semantic view selector
    sv_options = {
        "FLEET_FINDER": "SEM_DEV.UNITED_RENTALS.FLEET_FINDER",
        "RENTAL_ANALYTICS": "SEM_DEV.UNITED_RENTALS.RENTAL_ANALYTICS",
    }
    selected_sv = st.selectbox("Semantic View", list(sv_options.keys()))
    semantic_view = sv_options[selected_sv]

    # Sample questions
    if selected_sv == "FLEET_FINDER":
        samples = [
            "How many pieces of equipment are available by category?",
            "Show me available boom lifts in the Southwest region",
            "Which branches have the most idle equipment?",
            "What is the average daily rate by equipment category?",
            "How many pieces of equipment have active fault codes?",
        ]
    else:
        samples = [
            "What is total rental revenue by region?",
            "Show average rental duration by equipment category",
            "Which customers have the highest rental spend?",
            "How many active contracts are there by region?",
            "What is the revenue breakdown by rental term?",
        ]

    st.caption("Sample questions:")
    sample_cols = st.columns(len(samples))
    for i, q in enumerate(samples):
        with sample_cols[i]:
            if st.button(q, key=f"sample_{i}", use_container_width=True):
                st.session_state.analyst_input = q

    # Chat interface
    if "analyst_history" not in st.session_state:
        st.session_state.analyst_history = []

    # Display history
    for entry in st.session_state.analyst_history:
        with st.chat_message("user"):
            st.write(entry["question"])
        with st.chat_message("assistant"):
            if entry.get("text"):
                st.write(entry["text"])
            if entry.get("sql"):
                with st.expander("Generated SQL"):
                    st.code(entry["sql"], language="sql")
            if entry.get("results") is not None and not entry["results"].empty:
                st.dataframe(entry["results"], use_container_width=True, hide_index=True)

                # If results have lat/lon, show on map
                lat_cols = [c for c in entry["results"].columns if "LAT" in c.upper()]
                lon_cols = [c for c in entry["results"].columns if "LON" in c.upper()]
                if lat_cols and lon_cols:
                    map_df = entry["results"].rename(columns={
                        lat_cols[0]: "latitude",
                        lon_cols[0]: "longitude",
                    })
                    if "latitude" in map_df.columns and "longitude" in map_df.columns:
                        map_df = map_df.dropna(subset=["latitude", "longitude"])
                        if not map_df.empty:
                            st.map(map_df[["latitude", "longitude"]])

            if entry.get("error"):
                st.error(entry["error"])

    # Input
    default_input = st.session_state.pop("analyst_input", "")
    prompt = st.chat_input("Ask about fleet or rentals...", key="analyst_chat")
    if default_input and not prompt:
        prompt = default_input

    if prompt:
        with st.chat_message("user"):
            st.write(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                response, error = call_cortex_analyst(prompt, semantic_view)

            entry = {"question": prompt, "text": None, "sql": None, "results": None, "error": None}

            if error:
                st.error(f"Cortex Analyst error: {error}")
                entry["error"] = error
            elif response:
                sql, text = parse_analyst_response(response)
                if text:
                    st.write(text)
                    entry["text"] = text
                if sql:
                    with st.expander("Generated SQL"):
                        st.code(sql, language="sql")
                    entry["sql"] = sql

                    # Execute the generated SQL
                    try:
                        session = get_session()
                        result_df = session.sql(sql).to_pandas()
                        st.dataframe(result_df, use_container_width=True, hide_index=True)
                        entry["results"] = result_df

                        # Auto-map if geospatial columns found
                        lat_cols = [c for c in result_df.columns if "LAT" in c.upper()]
                        lon_cols = [c for c in result_df.columns if "LON" in c.upper()]
                        if lat_cols and lon_cols:
                            map_df = result_df.rename(columns={
                                lat_cols[0]: "latitude",
                                lon_cols[0]: "longitude",
                            })
                            map_df = map_df.dropna(subset=["latitude", "longitude"])
                            if not map_df.empty:
                                st.map(map_df[["latitude", "longitude"]])
                    except Exception as exec_err:
                        st.error(f"SQL execution error: {exec_err}")
                        entry["error"] = str(exec_err)

            st.session_state.analyst_history.append(entry)

    # Clear history
    if st.session_state.analyst_history:
        if st.button("Clear History"):
            st.session_state.analyst_history = []
            st.rerun()


# ============================================================================
# MAIN
# ============================================================================

def main():
    page = render_sidebar()
    if page == "Fleet Finder":
        render_fleet_finder()
    elif page == "Cortex Analyst":
        render_cortex_page()


if __name__ == "__main__":
    main()
