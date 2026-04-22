import streamlit as st
import pandas as pd
from google.cloud import bigquery
import pydeck as pdk
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import textwrap

# Setup
st.set_page_config(page_title="Home Price Analytics", layout="wide")

# Inject Custom CSS to match the Stitch "Refined Home Price Dashboard" design
st.markdown("""
<style>
    /* Import fonts */
    @import url('https://fonts.googleapis.com/css2?family=Manrope:wght@400;700;800&family=Inter:wght@400;500;600&display=swap');
    @import url('https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap');
    
    html, body, [class*="css"] {
        font-family: 'Inter', sans-serif;
        background-color: #f8f9fa;
        color: #191c1d;
    }
    
    .stApp {
        background-color: #f8f9fa;
    }
    
    /* Typography */
    h1, h2, h3, .font-headline {
        font-family: 'Manrope', sans-serif !important;
    }
    
    .page-title {
        font-family: 'Manrope', sans-serif;
        font-size: 1.875rem;
        font-weight: 800;
        color: #035279;
        margin-bottom: 0.25rem;
    }
    .page-subtitle {
        font-size: 0.875rem;
        color: #71787f;
        margin-bottom: 2rem;
    }
    
    /* KPI Cards */
    .kpi-card {
        background-color: #ffffff;
        padding: 1.5rem;
        border-radius: 0.5rem;
        box-shadow: 0 8px 24px rgba(25,28,29,0.06);
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }
    .kpi-title {
        font-size: 0.875rem;
        font-weight: 500;
        color: #41474e;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }
    .kpi-value {
        font-family: 'Manrope', sans-serif;
        font-size: 2.25rem;
        font-weight: 800;
        color: #035279;
        letter-spacing: -0.02em;
    }
    .kpi-value-error {
        color: #ba1a1a;
    }
    .kpi-footer {
        font-size: 0.75rem;
        font-weight: 500;
        color: #035279;
        display: flex;
        align-items: center;
        gap: 0.25rem;
    }
    .kpi-card-error {
        position: relative;
        overflow: hidden;
    }
    .kpi-card-error::before {
        content: '';
        position: absolute;
        top: 0; left: 0; right: 0; bottom: 0;
        background-color: rgba(255, 218, 214, 0.2);
        z-index: 0;
    }
    .kpi-card-error > * {
        position: relative;
        z-index: 1;
    }
    
    /* Section containers */
    .section-container {
        background-color: #ffffff;
        padding: 2rem;
        border-radius: 0.5rem;
        box-shadow: 0 8px 24px rgba(25,28,29,0.06);
        margin-bottom: 1.5rem;
    }
    .section-title {
        font-family: 'Manrope', sans-serif;
        font-size: 1.5rem;
        font-weight: 700;
        color: #035279;
        letter-spacing: -0.02em;
        margin-bottom: 1rem;
    }
    
    .kpi-card {
        height: 100%;
        display: flex;
        flex-direction: column;
    }
</style>
""", unsafe_allow_html=True)

# Fetch Data
@st.cache_data(ttl=3600)
def load_data():
    try:
        client = bigquery.Client()
        query_trends = """
        SELECT * FROM `home-prices-59122.bend_or.mrt_bend_or__anomalies`
        ORDER BY dim_collected_date ASC
        """
        
        query_listings = """
        SELECT * FROM `home-prices-59122.bend_or.mrt_bend_or__listings`
        """
        df_trends = client.query(query_trends).to_dataframe()
        df_listings = client.query(query_listings).to_dataframe()
        return df_trends, df_listings
    except Exception as e:
        # Fallback for local testing without creds or if tables don't exist yet
        st.warning(f"Could not load from BigQuery, using mock data. Error: {e}")
        dates = pd.date_range(start='2024-01-01', periods=52, freq='W')
        df_trends = pd.DataFrame({
            'dim_collected_date': dates,
            'is_target_segment': 'all',
            'met_price_median': [400000 + i*1000 + (i%4)*5000 for i in range(52)],
            'met_price_avg': [410000 + i*1050 for i in range(52)],
            'met_listings_count': [1000 + (i%10)*20 for i in range(52)],
            'is_price_median_anomaly': [False]*50 + [True, False],
            'met_price_median_lower_bound': [390000 + i*1000 for i in range(52)],
            'met_price_median_upper_bound': [420000 + i*1000 for i in range(52)],
        })
        df_listings = pd.DataFrame({
            'id': ['INV-001', 'INV-002', 'INV-003', 'INV-004'],
            'info_street1': ['1428 Elm Street', '9000 Hal Avenue', '31 Spooner Street', '742 Evergreen Terrace'],
            'dim_city': ['Bend', 'Bend', 'Bend', 'Bend'],
            'dim_zip': ['97701', '97702', '97701', '97702'],
            'met_price': [450000, 1200000, 320000, 385000],
            'met_price_per_sqft': [300, 400, 250, 280],
            'info_latitude': [44.0582, 44.0500, 44.0600, 44.0400],
            'info_longitude': [-121.3153, -121.3200, -121.3000, -121.3300],
            'is_target_segment': [True]*4
        })
        return df_trends, df_listings

df_trends, df_listings = load_data()

# Header
st.markdown('<div class="page-title">Bend Home Prices</div>', unsafe_allow_html=True)
st.markdown('<div class="page-subtitle">Woof-esque Analytical Engine</div>', unsafe_allow_html=True)

# Create placeholder for KPIs at the top
kpi_container = st.container()
st.write("") # Spacer

# Filters Row
with st.container(border=True):
    fc1, fc2, fc3, fc4 = st.columns(4)
    with fc1:
        metric_map = {
            "Median Price": ("met_price_median", "is_price_median_anomaly"),
            "Average Price": ("met_price_avg", "is_price_avg_anomaly"),
            "Median Price / SqFt": ("met_price_per_sqft_median", "is_price_per_sqft_median_anomaly"),
            "Average Price / SqFt": ("met_price_per_sqft_avg", "is_price_per_sqft_avg_anomaly")
        }
        selected_metric_labels = st.multiselect("Metric Timeseries", list(metric_map.keys()), default=["Median Price"])
        
    with fc2:
        listed_end = pd.to_datetime('today').normalize()
        listed_start = listed_end - pd.Timedelta(days=28)
        listed_date_range = st.date_input("Listed Date", value=(listed_start, listed_end))
        
    with fc3:
        if not df_trends.empty:
            min_date = pd.to_datetime(df_trends['dim_collected_date']).min()
            max_date = pd.to_datetime(df_trends['dim_collected_date']).max()
        else:
            min_date = pd.to_datetime('2024-01-01')
            max_date = pd.to_datetime('2024-12-31')
            
        collected_date_range = st.date_input("Collected Date", value=(min_date, max_date))
    with fc4:
        st.write("") # push down slightly
        show_estimates = st.checkbox("Show Estimates", value=True)
        highlight_anomalies = st.checkbox("Highlight Anomalies", value=True)
        target_homes = st.checkbox("Target Homes", value=True)

# --- Apply Collected Date Filter (Trends) ---
if isinstance(collected_date_range, tuple) and len(collected_date_range) == 2:
    col_start, col_end = pd.to_datetime(collected_date_range[0]), pd.to_datetime(collected_date_range[1])
elif isinstance(collected_date_range, tuple) and len(collected_date_range) == 1:
    col_start = col_end = pd.to_datetime(collected_date_range[0])
else:
    col_start = col_end = pd.to_datetime(collected_date_range)

if not df_trends.empty:
    df_trends['dim_collected_date'] = pd.to_datetime(df_trends['dim_collected_date'])
    df_trends = df_trends[(df_trends['dim_collected_date'] >= col_start) & (df_trends['dim_collected_date'] <= col_end)]
    if target_homes and 'is_target_segment' in df_trends.columns:
        df_trends = df_trends[df_trends['is_target_segment'].astype(str).str.lower() == 'true']
    elif not target_homes and 'is_target_segment' in df_trends.columns:
        df_trends = df_trends[df_trends['is_target_segment'].astype(str).str.lower() == 'all']

# --- Apply Listed Date Filter (Listings) ---
if isinstance(listed_date_range, tuple) and len(listed_date_range) == 2:
    list_start, list_end = pd.to_datetime(listed_date_range[0]), pd.to_datetime(listed_date_range[1])
elif isinstance(listed_date_range, tuple) and len(listed_date_range) == 1:
    list_start = list_end = pd.to_datetime(listed_date_range[0])
else:
    list_start = list_end = pd.to_datetime(listed_date_range)

if not df_listings.empty:
    if 'dim_listed_date' in df_listings.columns:
        df_listings['dim_listed_date_dt'] = pd.to_datetime(df_listings['dim_listed_date'], errors='coerce')
        df_listings = df_listings[
            (df_listings['dim_listed_date_dt'] >= list_start) & 
            (df_listings['dim_listed_date_dt'] <= list_end)
        ]
        df_listings = df_listings.drop(columns=['dim_listed_date_dt'])
        
    if target_homes and 'is_target' in df_listings.columns:
        df_listings = df_listings[df_listings['is_target'] == True]

# --- Render KPIs ---
with kpi_container:
    col1, col2, col3, col4 = st.columns(4)
    
    latest_trend = df_trends.iloc[-1] if not df_trends.empty else pd.Series()
    median_price = latest_trend.get('met_price_median', 0)
    avg_4wk = latest_trend.get('met_04_week_ma', 0)
    listings_count = len(df_listings)
    anomalies_count = df_trends['is_price_median_anomaly'].sum() if not df_trends.empty and 'is_price_median_anomaly' in df_trends.columns else 0

    with col1:
        st.markdown(f'''
        <div class="kpi-card">
            <span class="kpi-title">Median Home Price</span>
            <span class="kpi-value">${median_price/1000:,.0f}k</span>
            <span class="kpi-footer"><span style="font-weight:700; color:#035279;">${avg_4wk/1000:,.0f}k</span> 4-wk avg.</span>
        </div>
        ''', unsafe_allow_html=True)

    with col2:
        st.markdown('''
        <div class="kpi-card">
            <span class="kpi-title">YoY Growth</span>
            <span class="kpi-value">--</span>
            <span class="kpi-footer" style="color: #71787f;"><span class="material-symbols-outlined" style="font-size:16px;">horizontal_rule</span>Insufficient Data</span>
        </div>
        ''', unsafe_allow_html=True)

    with col3:
        st.markdown(f'''
        <div class="kpi-card">
            <span class="kpi-title">Listings</span>
            <span class="kpi-value">{listings_count:,.0f}</span>
            <span class="kpi-footer">Matching criteria</span>
        </div>
        ''', unsafe_allow_html=True)

    with col4:
        st.markdown(f'''
        <div class="kpi-card kpi-card-error">
            <span class="kpi-title">Anomalies Detected</span>
            <span class="kpi-value kpi-value-error">{anomalies_count}</span>
            <span class="kpi-footer" style="color: #ba1a1a;">Requires attention</span>
        </div>
        ''', unsafe_allow_html=True)

st.write("") # Spacer

# Main Trend Chart
with st.container(border=True):
    st.markdown('<div class="section-title">Home Price Trends & Forecast</div>', unsafe_allow_html=True)

    if not df_trends.empty and selected_metric_labels:
        fig = make_subplots(specs=[[{"secondary_y": True}]])
        colors = ['#035279', '#0059bb', '#2c6a93', '#71787f']
        
        has_primary = False
        has_secondary = False

        for i, label in enumerate(selected_metric_labels):
            metric_col, anomaly_col = metric_map[label]
            is_secondary = "SqFt" in label
            
            if is_secondary:
                has_secondary = True
            else:
                has_primary = True
                
            color = colors[i % len(colors)]
            
            # Main Line
            fig.add_trace(
                go.Scatter(
                    x=df_trends['dim_collected_date'], 
                    y=df_trends[metric_col], 
                    mode='lines', 
                    name=label,
                    line=dict(color=color)
                ),
                secondary_y=is_secondary
            )
            
            # Add Estimates (Forecast Bounds)
            if show_estimates:
                upper_bound_col = f'{metric_col}_upper_bound'
                lower_bound_col = f'{metric_col}_lower_bound'
                if upper_bound_col in df_trends.columns and lower_bound_col in df_trends.columns:
                    fill_rgba = 'rgba(203, 230, 255, 0.3)' if i == 0 else 'rgba(113, 120, 127, 0.15)'
                    fig.add_trace(
                        go.Scatter(
                            x=df_trends['dim_collected_date'], 
                            y=df_trends[upper_bound_col], 
                            mode='lines',
                            line=dict(color='rgba(255,255,255,0)'), 
                            showlegend=False, 
                            name=f'{label} Upper'
                        ),
                        secondary_y=is_secondary
                    )
                    fig.add_trace(
                        go.Scatter(
                            x=df_trends['dim_collected_date'], 
                            y=df_trends[lower_bound_col], 
                            mode='lines',
                            fill='tonexty', 
                            fillcolor=fill_rgba, 
                            line=dict(color='rgba(255,255,255,0)'), 
                            showlegend=False, 
                            name=f'{label} Lower'
                        ),
                        secondary_y=is_secondary
                    )
            
            # Add Anomalies
            if highlight_anomalies and anomaly_col in df_trends.columns:
                anomalies_df = df_trends[df_trends[anomaly_col] == True]
                if not anomalies_df.empty:
                    fig.add_trace(
                        go.Scatter(
                            x=anomalies_df['dim_collected_date'], 
                            y=anomalies_df[metric_col],
                            mode='markers', 
                            marker=dict(color='#ba1a1a', size=8, line=dict(color='white', width=1)),
                            name=f'{label} Anomaly',
                            showlegend=False
                        ),
                        secondary_y=is_secondary
                    )
            
        y1_title = "Price ($)" if has_primary else ""
        y2_title = "Price / SqFt ($)" if has_secondary else ""

        fig.update_layout(
            plot_bgcolor='rgba(0,0,0,0)',
            paper_bgcolor='rgba(0,0,0,0)',
            margin=dict(l=0, r=0, t=10, b=0),
            xaxis_title="",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
        )
        fig.update_xaxes(
            showgrid=True, 
            gridwidth=1, 
            gridcolor='#e1e3e4',
            tickmode='array',
            tickvals=df_trends['dim_collected_date'].unique(),
            tickformat="%b %d",
            tickangle=-45
        )
        fig.update_yaxes(title_text=y1_title, secondary_y=False, showgrid=True, gridwidth=1, gridcolor='#e1e3e4')
        if has_secondary:
            fig.update_yaxes(title_text=y2_title, secondary_y=True, showgrid=False)
            
        st.plotly_chart(fig, use_container_width=True)

st.write("") # Spacer

# Geographic Map
with st.container(border=True):
    st.markdown('<div class="section-title">Geographic Price Distribution</div>', unsafe_allow_html=True)
    if not df_listings.empty and 'info_latitude' in df_listings.columns:
        df_map = df_listings.dropna(subset=['info_latitude', 'info_longitude']).copy()
        df_map = df_map.rename(columns={'info_latitude': 'latitude', 'info_longitude': 'longitude'})
        
        # Format columns for the tooltip
        df_map['price_formatted'] = df_map['met_price'].apply(lambda x: f"${x:,.0f}" if pd.notnull(x) else "Unknown")
        if 'dim_listed_date' in df_map.columns:
            df_map['listed_date_str'] = pd.to_datetime(df_map['dim_listed_date']).dt.strftime('%b %d, %Y')
        else:
            df_map['listed_date_str'] = "Unknown"
            
        # Provide a fallback for missing addresses
        df_map['address_str'] = df_map['info_street1'].fillna("Unknown Address")

        df_map_display = df_map.rename(columns={
            'address_str': 'Address',
            'listed_date_str': 'Listed',
            'price_formatted': 'Price'
        })

        fig = px.scatter_mapbox(
            df_map_display,
            lat="latitude",
            lon="longitude",
            hover_name="Address",
            hover_data={
                "latitude": False,
                "longitude": False,
                "Listed": True,
                "Price": True
            },
            zoom=12.5,
            center=dict(lat=df_map_display["latitude"].mean(), lon=df_map_display["longitude"].mean())
        )
        
        fig.update_traces(marker=dict(size=14, color='#035279', opacity=0.9))
        fig.update_layout(
            mapbox_style="open-street-map",
            margin={"r":0,"t":0,"l":0,"b":0},
            hoverlabel=dict(bgcolor="white", font_family="Inter")
        )
        
        st.plotly_chart(fig, use_container_width=True)

st.write("") # Spacer

# Detailed Table
with st.container(border=True):
    st.markdown('<div class="section-title">Detailed Home Inventory</div>', unsafe_allow_html=True)
    if not df_listings.empty:
        if 'met_price_vs_comps_ratio' in df_listings.columns:
            df_display = df_listings.sort_values(by='met_price_vs_comps_ratio', ascending=True)
        else:
            df_display = df_listings
        st.dataframe(df_display, use_container_width=True, hide_index=True)
