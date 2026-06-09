"""Workday HCM -> ontology mapping (curated).

Reports (from the main generator's WorkdayGenerator):
  Workers           -> wd:Worker
  Organizations     -> wd:Organization
  Job_Profiles      -> wd:JobProfile
  Compensation      -> wd:Compensation     (Worker_WID -> Worker)
  Time_Off          -> wd:TimeOff          (Worker_WID -> Worker)
  Benefit_Elections -> wd:BenefitElection  (Worker_WID -> Worker)
"""
from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap

SPEC = MappingSpec(
    system="workday",
    namespace_prefix="wd",
    tables=[
        TableMap(
            table="Workers", class_iri="wd:Worker", uid_prefix="WD-WKR", key="Worker_WID",
            label=lambda r: f"{r.get('Legal_First_Name')} {r.get('Legal_Last_Name')}",
            literals=[
                PropMap("Legal_First_Name", "wd:firstName"),
                PropMap("Legal_Last_Name", "wd:lastName"),
                PropMap("Employee_ID", "wd:employeeId"),
                PropMap("Email_Work", "schema:email"),
                PropMap("Gender", "wd:gender"),
                PropMap("Job_Title", "schema:name"),
                PropMap("Job_Family", "wd:jobFamily"),
                PropMap("Job_Level", "wd:jobLevel"),
                PropMap("Worker_Type", "wd:workerType"),
                PropMap("Active_Status", "wd:activeStatus"),
                PropMap("Hire_Date", "wd:hireDate", "xsd:date"),
                PropMap("Annual_Salary", "wd:annualSalary", "xsd:decimal"),
                PropMap("Cost_Center", "wd:costCenter"),
                PropMap("State_Province", "schema:addressRegion"),
            ],
        ),
        TableMap(
            table="Organizations", class_iri="wd:Organization", uid_prefix="WD-ORG",
            key="Organization_WID", label="Organization_Name",
            literals=[
                PropMap("Organization_Name", "schema:name"),
                PropMap("Organization_Code", "wd:organizationCode"),
                PropMap("Organization_Type", "wd:organizationType"),
                PropMap("Organization_Subtype", "wd:organizationSubtype"),
            ],
        ),
        TableMap(
            table="Job_Profiles", class_iri="wd:JobProfile", uid_prefix="WD-JP",
            key="Job_Profile_WID", label="Job_Profile_Name",
            literals=[
                PropMap("Job_Profile_Name", "schema:name"),
                PropMap("Job_Code", "wd:jobCode"),
                PropMap("Job_Family_Name", "wd:jobFamily"),
                PropMap("Job_Level", "wd:jobLevel"),
                PropMap("Management_Level", "wd:managementLevel"),
            ],
        ),
        TableMap(
            table="Compensation", class_iri="wd:Compensation", uid_prefix="WD-COMP",
            key="Compensation_WID", label=lambda r: f"Compensation {r.get('Compensation_Plan')}",
            literals=[
                PropMap("Compensation_Plan", "schema:name"),
                PropMap("Base_Pay_Amount", "wd:basePayAmount", "xsd:decimal"),
                PropMap("Total_Compensation", "wd:totalCompensation", "xsd:decimal"),
                PropMap("Compensation_Grade", "wd:compensationGrade"),
                PropMap("Compa_Ratio", "wd:compaRatio", "xsd:decimal"),
                PropMap("Effective_Date", "wd:effectiveDate", "xsd:date"),
            ],
            edges=[EdgeMap("Worker_WID", "wd:forWorker", "Workers")],
        ),
        TableMap(
            table="Time_Off", class_iri="wd:TimeOff", uid_prefix="WD-TO",
            key="Time_Off_Request_WID", label=lambda r: f"{r.get('Time_Off_Type')} time off",
            literals=[
                PropMap("Time_Off_Type", "schema:name"),
                PropMap("Start_Date", "wd:startDate", "xsd:date"),
                PropMap("End_Date", "wd:endDate", "xsd:date"),
                PropMap("Total_Days", "wd:totalDays", "xsd:decimal"),
                PropMap("Status", "wd:status"),
            ],
            edges=[EdgeMap("Worker_WID", "wd:forWorker", "Workers")],
        ),
        TableMap(
            table="Benefit_Elections", class_iri="wd:BenefitElection", uid_prefix="WD-BEN",
            key="Benefit_Election_WID",
            label=lambda r: f"{r.get('Benefit_Plan_Type')}: {r.get('Benefit_Plan_Name')}",
            literals=[
                PropMap("Benefit_Plan_Name", "schema:name"),
                PropMap("Benefit_Plan_Type", "wd:benefitPlanType"),
                PropMap("Coverage_Level", "wd:coverageLevel"),
                PropMap("Employee_Cost", "wd:employeeCost", "xsd:decimal"),
                PropMap("Employer_Cost", "wd:employerCost", "xsd:decimal"),
            ],
            edges=[EdgeMap("Worker_WID", "wd:forWorker", "Workers")],
        ),
    ],
)
