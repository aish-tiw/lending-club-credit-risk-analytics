-- Lending Club Credit Risk Analytics
-- Platform: Databricks SQL
--
-- These queries use two Delta tables prepared in the project notebook:
--   workspace.credit_risk.loan_portfolio
--   workspace.credit_risk.mature_loan_outcomes


-- Question 1: What is the size and current risk position of the portfolio?

SELECT
    COUNT(*) AS total_loans,
    ROUND(SUM(funded_amnt), 2) AS total_funded_amount,
    ROUND(AVG(funded_amnt), 2) AS average_funded_amount,
    ROUND(AVG(int_rate), 2) AS average_interest_rate,
    ROUND(SUM(out_prncp), 2) AS outstanding_principal,
    SUM(CASE WHEN status_group = 'Current' THEN 1 ELSE 0 END) AS current_loans,
    ROUND(100.0 * SUM(CASE WHEN status_group = 'Current' THEN 1 ELSE 0 END) / COUNT(*), 2) AS current_loan_percentage,
    SUM(CASE WHEN status_group = 'Delinquent' THEN 1 ELSE 0 END) AS delinquent_loans,
    ROUND(100.0 * SUM(CASE WHEN status_group = 'Delinquent' THEN 1 ELSE 0 END) / COUNT(*), 2) AS delinquent_loan_percentage,
    ROUND(SUM(CASE WHEN status_group = 'Delinquent' THEN out_prncp ELSE 0 END), 2) AS delinquent_exposure,
    ROUND(100.0 * SUM(CASE WHEN status_group = 'Delinquent' THEN out_prncp ELSE 0 END) / SUM(out_prncp), 2) AS delinquent_exposure_percentage
FROM workspace.credit_risk.loan_portfolio;


-- Question 2: Which grades combine higher historical default risk with substantial exposure?

WITH portfolio_by_grade AS (
    SELECT
        grade,
        COUNT(*) AS portfolio_loans,
        ROUND(SUM(out_prncp), 2) AS outstanding_principal,
        ROUND(SUM(CASE WHEN status_group = 'Delinquent' THEN out_prncp ELSE 0 END), 2) AS delinquent_exposure
    FROM workspace.credit_risk.loan_portfolio
    WHERE grade IS NOT NULL
    GROUP BY grade
),
outcomes_by_grade AS (
    SELECT
        grade,
        COUNT(*) AS mature_loans,
        SUM(default_flag) AS defaulted_loans,
        ROUND(AVG(default_flag) * 100, 2) AS historical_default_rate
    FROM workspace.credit_risk.mature_loan_outcomes
    WHERE grade IS NOT NULL
    GROUP BY grade
)
SELECT
    p.grade,
    p.portfolio_loans,
    o.mature_loans,
    o.defaulted_loans,
    o.historical_default_rate,
    p.outstanding_principal,
    p.delinquent_exposure
FROM portfolio_by_grade p
LEFT JOIN outcomes_by_grade o ON p.grade = o.grade
ORDER BY p.grade;


-- Question 3: Does loan term affect default risk within each grade?

WITH segment_summary AS (
    SELECT
        grade,
        term_months,
        COUNT(*) AS mature_loans,
        SUM(default_flag) AS defaulted_loans,
        ROUND(AVG(default_flag) * 100, 2) AS historical_default_rate,
        ROUND(AVG(funded_amnt), 2) AS average_funded_amount,
        ROUND(SUM(CASE WHEN default_flag = 1 THEN funded_amnt ELSE 0 END), 2) AS defaulted_funded_exposure
    FROM workspace.credit_risk.mature_loan_outcomes
    WHERE grade IS NOT NULL AND term_months IS NOT NULL
    GROUP BY grade, term_months
)
SELECT
    grade,
    term_months,
    mature_loans,
    defaulted_loans,
    historical_default_rate,
    average_funded_amount,
    defaulted_funded_exposure,
    DENSE_RANK() OVER (ORDER BY historical_default_rate DESC) AS risk_rank
FROM segment_summary
ORDER BY grade, term_months;


-- Question 4: Which loan purposes create the greatest risk and exposure?

WITH portfolio_purpose AS (
    SELECT
        purpose,
        COUNT(*) AS portfolio_loans,
        ROUND(SUM(out_prncp), 2) AS outstanding_principal,
        ROUND(SUM(CASE WHEN status_group = 'Delinquent' THEN out_prncp ELSE 0 END), 2) AS delinquent_exposure
    FROM workspace.credit_risk.loan_portfolio
    GROUP BY purpose
),
outcome_purpose AS (
    SELECT
        purpose,
        COUNT(*) AS mature_loans,
        ROUND(AVG(default_flag) * 100, 2) AS historical_default_rate,
        ROUND(SUM(CASE WHEN default_flag = 1 THEN funded_amnt ELSE 0 END), 2) AS defaulted_funded_exposure
    FROM workspace.credit_risk.mature_loan_outcomes
    GROUP BY purpose
)
SELECT
    o.purpose,
    o.mature_loans,
    o.historical_default_rate,
    o.defaulted_funded_exposure,
    p.portfolio_loans,
    p.outstanding_principal,
    p.delinquent_exposure
FROM outcome_purpose o
LEFT JOIN portfolio_purpose p ON o.purpose = p.purpose
ORDER BY o.defaulted_funded_exposure DESC;


-- Question 5: How did lending activity change over time?

WITH yearly_lending AS (
    SELECT
        issue_year,
        COUNT(*) AS loan_count,
        SUM(funded_amnt) AS total_funded_amount,
        AVG(funded_amnt) AS average_funded_amount,
        AVG(int_rate) AS average_interest_rate
    FROM workspace.credit_risk.loan_portfolio
    WHERE issue_year IS NOT NULL
    GROUP BY issue_year
)
SELECT
    issue_year,
    loan_count,
    ROUND(total_funded_amount, 2) AS total_funded_amount,
    ROUND(average_funded_amount, 2) AS average_funded_amount,
    ROUND(average_interest_rate, 2) AS average_interest_rate,
    ROUND(
        (total_funded_amount - LAG(total_funded_amount) OVER (ORDER BY issue_year))
        / LAG(total_funded_amount) OVER (ORDER BY issue_year) * 100,
        2
    ) AS funded_amount_growth_percentage
FROM yearly_lending
ORDER BY issue_year;


-- Question 6: How is borrower debt burden related to default risk?

WITH dti_segments AS (
    SELECT
        CASE
            WHEN dti < 0 THEN 'Invalid'
            WHEN dti < 10 THEN 'Under 10'
            WHEN dti < 20 THEN '10-19.99'
            WHEN dti < 30 THEN '20-29.99'
            WHEN dti < 40 THEN '30-39.99'
            ELSE '40 or more'
        END AS dti_band,
        CASE
            WHEN dti < 0 THEN 0
            WHEN dti < 10 THEN 1
            WHEN dti < 20 THEN 2
            WHEN dti < 30 THEN 3
            WHEN dti < 40 THEN 4
            ELSE 5
        END AS band_order,
        default_flag,
        funded_amnt
    FROM workspace.credit_risk.mature_loan_outcomes
)
SELECT
    dti_band,
    COUNT(*) AS mature_loans,
    SUM(default_flag) AS defaulted_loans,
    ROUND(AVG(default_flag) * 100, 2) AS historical_default_rate,
    ROUND(AVG(funded_amnt), 2) AS average_funded_amount,
    ROUND(SUM(CASE WHEN default_flag = 1 THEN funded_amnt ELSE 0 END), 2) AS defaulted_funded_exposure
FROM dti_segments
GROUP BY dti_band, band_order
ORDER BY band_order;
