# Sample Questions for Cortex Analyst

## Overview

This document provides sample natural language questions for each semantic view. Use these to test Cortex Analyst functionality and demonstrate the power of semantic models.

## Sales Analytics (SEM_SALES.SALES_ANALYTICS)

### Revenue Questions

- "What is total revenue by region this year?"
- "Show me monthly revenue trends for the last 12 months"
- "Which quarter had the highest sales?"
- "What's the average order value by sales channel?"
- "How does online revenue compare to field sales?"

### Order Questions

- "How many orders were placed last month?"
- "What's the order completion rate by region?"
- "Show cancelled orders by quarter"
- "Which day of week has the most orders?"
- "What's the average discount percentage applied?"

### Customer Questions

- "How many unique customers ordered in Q4?"
- "What is revenue per customer by segment?"
- "Show customer tier distribution with average order value"
- "Which customer region has the highest lifetime value?"

### Fulfillment Questions

- "What's the average days to ship by region?"
- "Show fulfillment time trends"
- "Which shipping method is most popular?"

## Customer Analytics (SEM_CUSTOMER.CUSTOMER_ANALYTICS)

### Segmentation Questions

- "How many customers are in each tier?"
- "What's the average lifetime value by segment?"
- "Show customer distribution by industry"
- "Which region has the most enterprise customers?"

### Health Questions

- "How many customers are at risk of churning?"
- "What percentage of customers are active?"
- "Show churn rate by tenure bucket"
- "Which customer segment has the highest retention?"

### Value Questions

- "What is total lifetime value by region?"
- "Show me the top customer tiers by revenue"
- "What's the average tenure by customer segment?"
- "How does lifetime value correlate with tenure?"

### Consent/Compliance Questions

- "How many customers have marketing consent?"
- "What percentage have GDPR delete requests?"
- "Show consent rates by region"

## Workforce Analytics (SEM_HR.WORKFORCE_ANALYTICS)

### Headcount Questions

- "What is total headcount by department?"
- "How many employees work remotely?"
- "Show headcount by job level"
- "What percentage of employees are contractors?"

### Tenure Questions

- "What is average tenure by department?"
- "How many new hires joined this year?"
- "Show tenure distribution by age band"
- "Which department has the longest average tenure?"

### Demographics Questions

- "What is the age distribution across the company?"
- "Show gender breakdown by department"
- "What percentage of each level is remote?"

## Operations Analytics (SEM_OPERATIONS.OPERATIONS_METRICS)

### Daily Performance Questions

- "What was total revenue yesterday?"
- "Show daily order trends for this month"
- "Which day had the most orders?"
- "What's the weekend vs weekday revenue split?"

### Channel Questions

- "Which sales channel is most profitable?"
- "Show order count by channel over time"
- "What's the average order value by channel?"

### Regional Questions

- "Compare regional performance this quarter"
- "Which region has the best completion rate?"
- "Show revenue trends by region"

## Complex/Cross-Domain Questions

These questions require joining across multiple tables in the semantic view:

- "Show me enterprise customers in North America with orders over $5000"
- "What is revenue from new customers vs repeat customers?"
- "Compare order trends between fiscal quarters"
- "Which customer segments have the highest order frequency?"
- "Show me customers who haven't ordered in 90 days with high lifetime value"

## Questions by Difficulty

### Beginner (Single Metric)
- "What is total revenue?"
- "How many customers do we have?"
- "Show order count"

### Intermediate (Grouped)
- "Revenue by region"
- "Orders by status"
- "Customers by segment"

### Advanced (Filtered + Grouped)
- "Revenue by region for Q4 2024"
- "Enterprise customers by industry"
- "Completed orders by channel this month"

### Expert (Multiple Metrics + Calculations)
- "Revenue per customer by region and quarter"
- "Completion rate and average order value by channel"
- "Year-over-year revenue growth by segment"

## Tips for Best Results

1. **Be Specific**: "revenue by region" is better than "how are we doing"
2. **Include Time**: "this quarter" or "last 12 months" helps scope results
3. **Name Metrics**: Use terms like "revenue", "orders", "customers"
4. **Specify Dimensions**: "by region", "by segment", "by channel"

## Troubleshooting

If Cortex doesn't understand a question:
- Rephrase using dimension/metric names from the semantic view
- Break complex questions into simpler parts
- Check that you're using the correct semantic view

## Source System-Specific Questions

When using data from specific source systems, try these context-aware questions:

### SAP S/4HANA
- "Show me customer sales by VKORG (sales organization)"
- "What is total NETWR (net value) by month?"
- "List materials by MTART (material type)"
- "How many purchase orders by vendor LIFNR?"

### Salesforce
- "What is opportunity Amount by StageName?"
- "Show Cases by Status and Priority"
- "How many Leads converted this quarter?"
- "Campaign performance by Type"

### Oracle EBS
- "Show order totals by FLOW_STATUS_CODE"
- "What is AP invoice volume by vendor?"
- "AR aging by customer PARTY_ID"
- "GL journal entries by period"

### FHIR R4 Healthcare
- "Patient encounters by class (ambulatory, inpatient, emergency)"
- "Condition frequency by ICD-10 code"
- "Observation trends for vital signs"
- "Claims by type (institutional, professional, pharmacy)"

### Workday HCM
- "Headcount by Supervisory_Organization_Name"
- "Compensation by Job_Level"
- "Time off requests by type"
- "Benefits enrollment by plan"

### ServiceNow
- "Incidents by priority and category"
- "Change requests by risk level"
- "CMDB configuration items by class"
- "Knowledge article views by category"

---

*These questions are designed for the demo semantic views. Actual results depend on the source system and domain used when generating synthetic data.*

**Generating source-specific data:**
```bash
python data_generator.py --system sap --domain all --output ../data
python data_generator.py --system salesforce --domain sales --output ../data
python data_generator.py --system fhir --domain clinical --output ../data
```
