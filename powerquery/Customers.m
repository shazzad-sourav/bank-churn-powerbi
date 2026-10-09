// Power Query (M) for the "Customers" table
// How to use: Home > Get data > Blank query > Advanced Editor > paste this whole file.
// DataPath below already points at this project folder; change it only if you move the folder. Click Done,
// and rename the query to: Customers
let
    DataPath = "C:\Users\shazz\DataAnalyst\BankChurn-PowerBI\data\BankChurners.csv",

    Source = Csv.Document(
        File.Contents(DataPath),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    PromotedHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    // en-US culture so decimals like 12691.0 parse correctly on any Windows locale
    Typed = Table.TransformColumnTypes(
        PromotedHeaders,
        {
            {"CLIENTNUM", type text},
            {"Attrition_Flag", type text},
            {"Customer_Age", Int64.Type},
            {"Gender", type text},
            {"Dependent_count", Int64.Type},
            {"Education_Level", type text},
            {"Marital_Status", type text},
            {"Income_Category", type text},
            {"Card_Category", type text},
            {"Months_on_book", Int64.Type},
            {"Total_Relationship_Count", Int64.Type},
            {"Months_Inactive_12_mon", Int64.Type},
            {"Contacts_Count_12_mon", Int64.Type},
            {"Credit_Limit", type number},
            {"Total_Revolving_Bal", type number},
            {"Avg_Open_To_Buy", type number},
            {"Total_Amt_Chng_Q4_Q1", type number},
            {"Total_Trans_Amt", type number},
            {"Total_Trans_Ct", Int64.Type},
            {"Total_Ct_Chng_Q4_Q1", type number},
            {"Avg_Utilization_Ratio", type number}
        },
        "en-US"
    ),

    // ---- Target: 1 = churned, 0 = still a customer ----
    AddChurned = Table.AddColumn(Typed, "Churned",
        each if [Attrition_Flag] = "Attrited Customer" then 1 else 0, Int64.Type),
    AddStatus = Table.AddColumn(AddChurned, "Status",
        each if [Churned] = 1 then "Churned" else "Active", type text),

    // ---- Readable labels ----
    CleanGender = Table.ReplaceValue(
        Table.ReplaceValue(AddStatus, "F", "Female", Replacer.ReplaceValue, {"Gender"}),
        "M", "Male", Replacer.ReplaceValue, {"Gender"}),
    CleanIncome = Table.ReplaceValue(CleanGender, "Less than $40K", "< $40K",
        Replacer.ReplaceValue, {"Income_Category"}),

    // ---- Sort-order helper columns (use "Sort by column" in Power BI) ----
    AddIncomeSort = Table.AddColumn(CleanIncome, "Income Sort", each
        if [Income_Category] = "< $40K" then 1
        else if [Income_Category] = "$40K - $60K" then 2
        else if [Income_Category] = "$60K - $80K" then 3
        else if [Income_Category] = "$80K - $120K" then 4
        else if [Income_Category] = "$120K +" then 5
        else 6, Int64.Type),
    AddEducationSort = Table.AddColumn(AddIncomeSort, "Education Sort", each
        if [Education_Level] = "Uneducated" then 1
        else if [Education_Level] = "High School" then 2
        else if [Education_Level] = "College" then 3
        else if [Education_Level] = "Graduate" then 4
        else if [Education_Level] = "Post-Graduate" then 5
        else if [Education_Level] = "Doctorate" then 6
        else 7, Int64.Type),
    AddCardSort = Table.AddColumn(AddEducationSort, "Card Sort", each
        if [Card_Category] = "Blue" then 1
        else if [Card_Category] = "Silver" then 2
        else if [Card_Category] = "Gold" then 3
        else 4, Int64.Type),

    // ---- Bins ----
    AddAgeGroup = Table.AddColumn(AddCardSort, "Age Group", each
        if [Customer_Age] < 30 then "Under 30"
        else if [Customer_Age] < 40 then "30-39"
        else if [Customer_Age] < 50 then "40-49"
        else if [Customer_Age] < 60 then "50-59"
        else "60+", type text),
    AddAgeSort = Table.AddColumn(AddAgeGroup, "Age Sort", each
        if [Customer_Age] < 30 then 1
        else if [Customer_Age] < 40 then 2
        else if [Customer_Age] < 50 then 3
        else if [Customer_Age] < 60 then 4
        else 5, Int64.Type),
    AddTxnBand = Table.AddColumn(AddAgeSort, "Txn Count Band", each
        if [Total_Trans_Ct] < 40 then "Under 40"
        else if [Total_Trans_Ct] < 60 then "40-59"
        else if [Total_Trans_Ct] < 80 then "60-79"
        else "80+", type text),
    AddTxnSort = Table.AddColumn(AddTxnBand, "Txn Band Sort", each
        if [Total_Trans_Ct] < 40 then 1
        else if [Total_Trans_Ct] < 60 then 2
        else if [Total_Trans_Ct] < 80 then 3
        else 4, Int64.Type),
    AddRevolver = Table.AddColumn(AddTxnSort, "Carries Balance", each
        if [Total_Revolving_Bal] = 0 then "No balance" else "Carries balance", type text),

    // ---- Rule-based churn risk score (0-6): one point per warning sign ----
    AddFlagLowTxn   = Table.AddColumn(AddRevolver,   "Flag Low Txn",       each if [Total_Trans_Ct] < 60 then 1 else 0, Int64.Type),
    AddFlagDrop     = Table.AddColumn(AddFlagLowTxn, "Flag Activity Drop", each if [Total_Ct_Chng_Q4_Q1] < 0.6 then 1 else 0, Int64.Type),
    AddFlagNoBal    = Table.AddColumn(AddFlagDrop,   "Flag No Balance",    each if [Total_Revolving_Bal] = 0 then 1 else 0, Int64.Type),
    AddFlagContacts = Table.AddColumn(AddFlagNoBal,  "Flag High Contacts", each if [Contacts_Count_12_mon] >= 4 then 1 else 0, Int64.Type),
    AddFlagProducts = Table.AddColumn(AddFlagContacts, "Flag Few Products", each if [Total_Relationship_Count] <= 2 then 1 else 0, Int64.Type),
    AddFlagInactive = Table.AddColumn(AddFlagProducts, "Flag Inactive",    each if [Months_Inactive_12_mon] >= 3 then 1 else 0, Int64.Type),

    AddRiskScore = Table.AddColumn(AddFlagInactive, "Risk Score", each
        [Flag Low Txn] + [Flag Activity Drop] + [Flag No Balance]
        + [Flag High Contacts] + [Flag Few Products] + [Flag Inactive], Int64.Type),
    AddRiskTier = Table.AddColumn(AddRiskScore, "Risk Tier", each
        if [Risk Score] >= 3 then "High"
        else if [Risk Score] = 2 then "Medium"
        else "Low", type text),
    AddRiskSort = Table.AddColumn(AddRiskTier, "Risk Sort", each
        if [Risk Score] >= 3 then 1
        else if [Risk Score] = 2 then 2
        else 3, Int64.Type),

    Final = Table.RemoveColumns(AddRiskSort, {"Attrition_Flag"})
in
    Final
