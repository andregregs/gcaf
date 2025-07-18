#  [Merging Results from Different Explores in Looker](https://www.youtube.com/watch?v=IpJ8IXRaI90)


#### ⚠️ Disclaimer :
**Script dan panduan ini disediakan untuk tujuan edukasi agar Anda dapat memahami proses lab dengan lebih baik. Sebelum menggunakannya, disarankan untuk meninjau setiap langkah guna memperoleh pemahaman yang lebih mendalam. Pastikan untuk mematuhi ketentuan layanan Qwiklabs, karena tujuan utamanya adalah mendukung pengalaman belajar Anda.**


# Looker Data Merging and Dashboard Tutorial

## Lab Setup and Authentication

### Getting Started
1. **Start the Lab**
   - Click **Start Lab** when ready
   - Review lab credentials in the **Lab Details** pane
   - Complete payment if required

2. **Access Looker**
   - Click **Open Looker**
   - Use the provided credentials from Lab Details pane
   - Enter **Username** and **Password** in the login fields
   - Click **Log In**

⚠️ **Important**: Always use lab credentials, not personal Google Cloud or Looker accounts.

---

## Task 1: Create a Primary Query

The primary query serves as the foundation for merging multiple data sources.

### Steps:
1. **Navigate to Explore**
   - In Looker navigation menu → **Explore**
   - Under **FAA** → Click **Flights**

2. **Select Flight Details**
   - Expand **Flight Details** in the left pane
   - Select:
     - **Carrier**
     - **Flight Num**

3. **Add Origin Information**
   - Expand **Aircraft Origin**
   - Click **City**

4. **Add Metrics**
   - Expand **Flight Details**
   - Under **MEASURES** → Click **Cancelled Count**

5. **Apply Date Filter**
   - Expand **Arrival Date**
   - Hover over **Year** → Click **Filter by field**
   - Set filter: **"is in the year"** → Enter **2000**

6. **Execute Query**
   - Click **Run** to see results
   - Review flight details and cancellation data for year 2000

💡 **Tip**: Reorder fields by dragging and dropping in the right pane.

---

## Task 2: Add Secondary Source Query

Merge airport information with flight data to enrich the analysis.

### Steps:
1. **Access Merge Function**
   - In top right pane → Click **Settings** (gear icon)
   - Click **Merge Results**

2. **Select Airport Data**
   - In **Choose an Explore** window → Click **Airports**

3. **Configure Airport Fields**
   - In **All Fields** pane, select:
     - **City**
     - **Average Elevation**

4. **Execute and Save**
   - Click **Run** to preview results
   - Click **Save** to merge with primary query

⚠️ **Merge Requirements**: Ensure queries share at least one common dimension with exact matching values.

---

## Task 3: Configure Merge Rules and Execute

Looker automatically identifies merge dimensions and creates matching rules.

### Steps:
1. **Review Merge Rules**
   - Check **Merge Rules** section
   - Verify: **Primary (Flights)** uses **Aircraft Origin City**
   - Verify: **Secondary (Airports)** uses **Airports City**

2. **Adjust if Necessary**
   - Modify dropdowns to ensure correct dimension matching
   - Confirm merge rule alignment

3. **Execute Merged Query**
   - Click **Run** to view combined results
   - Click **Airports Average Elevation** to sort descending

4. **Explore Visualizations**
   - Expand **Visualization** pane
   - Test different chart options for optimal data presentation

---

## Task 4: Edit Merged Results

Enhance the analysis by adding destination airport information.

### Steps:
1. **Edit Primary Query**
   - In **Source Queries** pane → Click gear icon next to **Flights**
   - Click **Edit**

2. **Add Destination Data**
   - Click **All Fields**
   - Expand **Aircraft Destination**
   - Click **City**

3. **Apply Changes**
   - Click **Run** to preview modified query
   - Click **Save** to update primary source query

---

## Task 5: Create Dashboard

Save your merged analysis to a shareable dashboard.

### Steps:
1. **Prepare Visualization**
   - Expand **Visualization** pane
   - Select **Table** view

2. **Save to Dashboard**
   - Click gear icon in top right
   - Click **Save to Dashboard**

3. **Configure Dashboard**
   - **Title**: `Flight Cancellations & Elevation`
   - Click **New Dashboard**
   - **Dashboard Name**: `Airport Data`
   - Click **OK**

4. **Finalize**
   - Click **Save to Dashboard**
   - Access via green banner link or **Folders > Shared Folders**

---

## Key Learning Outcomes

### Data Merging Concepts
- **Primary Query**: Foundation dataset for analysis
- **Secondary Query**: Additional data source for enrichment
- **Merge Rules**: Dimension matching logic for combining datasets
- **Common Dimensions**: Shared fields enabling data joining

### Best Practices
- ✅ Ensure exact dimension value matching
- ✅ Include at least one common dimension in each query
- ✅ Test merge rules before finalizing
- ✅ Use appropriate visualizations for merged data
- ✅ Save important analyses to dashboards for sharing

### Dashboard Benefits
- **Centralized Analysis**: Single location for key insights
- **Collaboration**: Easy sharing with stakeholders
- **Reusability**: Saved configurations for future analysis
- **Visualization Options**: Multiple chart types for data presentation

---

## Troubleshooting Tips

### Common Issues
- **Merge Failures**: Check dimension value formats and naming
- **Missing Data**: Verify source query configurations
- **Performance**: Limit result sets for large datasets
- **Access Issues**: Confirm proper lab credentials usage

### Navigation Help
- **Folders > Shared Folders**: Access saved dashboards
- **Explore**: Return to data exploration interface
- **Settings Gear**: Access merge and configuration options
- **All Fields**: View available dimensions and measures