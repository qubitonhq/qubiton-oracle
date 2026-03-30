# API Examples

All 41 API methods with PL/SQL examples. Each method returns a `CLOB` containing the raw JSON response from the QubitOn API.

## Table of Contents

- [Address](#address)
- [Tax](#tax)
- [Bank](#bank)
- [Email and Phone](#email-and-phone)
- [Business Registration](#business-registration)
- [Peppol](#peppol)
- [Sanctions and Compliance](#sanctions-and-compliance)
- [EPA](#epa)
- [Healthcare](#healthcare)
- [Risk and Financial](#risk-and-financial)
- [ESG and Cybersecurity](#esg-and-cybersecurity)
- [Corporate Structure](#corporate-structure)
- [Industry](#industry)
- [Certification](#certification)
- [Classification](#classification)
- [Financial Ops](#financial-ops)
- [Supplier](#supplier)
- [Gender](#gender)
- [Reference](#reference)

---

## Address

### 1. validate_address

Validates a postal address against authoritative sources (USPS-certified for US addresses, 249 countries supported).

**Simple call:**

```sql
SELECT qubiton_api_pkg.validate_address(
    p_country       => 'US',
    p_address_line1 => '1600 Pennsylvania Ave NW'
) FROM DUAL;
```

**Full call with all parameters:**

```sql
SELECT qubiton_api_pkg.validate_address(
    p_country       => 'US',
    p_address_line1 => '1600 Pennsylvania Ave NW',
    p_city          => 'Washington',
    p_state         => 'DC',
    p_postal_code   => '20500',
    p_address_line2 => 'Suite 100'
) FROM DUAL;
```

**Using parse_result to check validity:**

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.validate_address(
        p_country       => 'US',
        p_address_line1 => '1600 Pennsylvania Ave NW',
        p_city          => 'Washington',
        p_state         => 'DC',
        p_postal_code   => '20500'
    );

    l_result := qubiton_api_pkg.parse_result(l_json);

    IF l_result.success AND l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Address is valid');
    ELSIF l_result.success AND NOT l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Address is invalid: ' || l_result.message);
    ELSE
        DBMS_OUTPUT.PUT_LINE('API error: ' || l_result.message);
    END IF;
END;
/
```

---

## Tax

### 2. validate_tax

Validates a tax identification number against government registries.

**Simple call:**

```sql
SELECT qubiton_api_pkg.validate_tax(
    p_tax_id  => 'DE123456789',
    p_country => 'DE'
) FROM DUAL;
```

**Full call with all parameters:**

```sql
SELECT qubiton_api_pkg.validate_tax(
    p_tax_id      => '12-3456789',
    p_country     => 'US',
    p_tax_id_type => 'EIN'
) FROM DUAL;
```

**Using parse_result:**

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.validate_tax(
        p_tax_id      => 'GB123456789',
        p_country     => 'GB',
        p_tax_id_type => 'VAT'
    );

    l_result := qubiton_api_pkg.parse_result(l_json);

    IF l_result.success AND l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Tax ID is valid');
    ELSIF l_result.success AND NOT l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Tax ID is invalid: ' || l_result.message);
    ELSE
        DBMS_OUTPUT.PUT_LINE('API error: ' || l_result.message);
    END IF;
END;
/
```

### 3. validate_tax_format

Validates the format of a tax ID without checking against a registry.

```sql
SELECT qubiton_api_pkg.validate_tax_format(
    p_tax_id  => 'DE123456789',
    p_country => 'DE'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_tax_format(
    p_tax_id      => 'DE123456789',
    p_country     => 'DE',
    p_tax_id_type => 'VAT'
) FROM DUAL;
```

---

## Bank

### 4. validate_bank_account

Validates bank account details (routing number, IBAN, SWIFT).

**Simple call:**

```sql
SELECT qubiton_api_pkg.validate_bank_account(
    p_country => 'US',
    p_routing_number => '021000021'
) FROM DUAL;
```

**Full call with all parameters:**

```sql
SELECT qubiton_api_pkg.validate_bank_account(
    p_country        => 'US',
    p_account_number => '1234567890',
    p_routing_number => '021000021',
    p_iban           => NULL,
    p_bank_code      => NULL,
    p_swift_code     => 'CHASUS33'
) FROM DUAL;
```

**Using parse_result:**

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.validate_bank_account(
        p_country => 'DE',
        p_iban    => 'DE89370400440532013000'
    );

    l_result := qubiton_api_pkg.parse_result(l_json);

    IF l_result.success AND l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Bank account is valid');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Validation result: ' || l_result.message);
    END IF;
END;
/
```

### 5. validate_bank_pro

Enhanced bank validation with account name matching.

```sql
SELECT qubiton_api_pkg.validate_bank_pro(
    p_country        => 'US',
    p_account_number => '1234567890',
    p_routing_number => '021000021'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_bank_pro(
    p_country        => 'US',
    p_account_number => '1234567890',
    p_routing_number => '021000021',
    p_iban           => NULL,
    p_bank_code      => NULL,
    p_swift_code     => 'CHASUS33',
    p_account_name   => 'Acme Corporation'
) FROM DUAL;
```

---

## Email and Phone

### 6. validate_email

Validates email address deliverability, domain, and syntax.

```sql
SELECT qubiton_api_pkg.validate_email(
    p_email => 'user@example.com'
) FROM DUAL;
```

### 7. validate_phone

Validates and formats phone numbers.

```sql
SELECT qubiton_api_pkg.validate_phone(
    p_phone_number => '+14155551234'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_phone(
    p_phone_number => '(415) 555-1234',
    p_country      => 'US'
) FROM DUAL;
```

---

## Business Registration

### 8. lookup_business_registration

Looks up company registration details from government registries.

**Simple call:**

```sql
SELECT qubiton_api_pkg.lookup_business_registration(
    p_company_name => 'Apple Inc',
    p_country      => 'US'
) FROM DUAL;
```

**Full call:**

```sql
SELECT qubiton_api_pkg.lookup_business_registration(
    p_company_name        => 'Apple Inc',
    p_country             => 'US',
    p_registration_number => '0000320193',
    p_state               => 'CA'
) FROM DUAL;
```

**Using parse_result (field: isRegistered):**

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.lookup_business_registration(
        p_company_name => 'Acme Ltd',
        p_country      => 'GB'
    );

    l_result := qubiton_api_pkg.parse_result(
        p_json       => l_json,
        p_field_name => 'isRegistered'
    );

    IF l_result.success AND l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('Company is registered');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Not found or error: ' || l_result.message);
    END IF;
END;
/
```

---

## Peppol

### 9. validate_peppol

Validates a Peppol participant identifier.

```sql
SELECT qubiton_api_pkg.validate_peppol(
    p_peppol_id => '0192:123456789',
    p_scheme_id => '0192'
) FROM DUAL;
```

---

## Sanctions and Compliance

### 10. check_sanctions

Screens entities against global sanctions lists (OFAC, EU, UN, UK HMT).

**Simple call:**

```sql
SELECT qubiton_api_pkg.check_sanctions(
    p_entity_name => 'John Smith'
) FROM DUAL;
```

**Full call:**

```sql
SELECT qubiton_api_pkg.check_sanctions(
    p_entity_name   => 'John Smith',
    p_entity_type   => 'INDIVIDUAL',
    p_country       => 'RU',
    p_date_of_birth => '1970-01-15',
    p_id_number     => 'AB1234567'
) FROM DUAL;
```

**Using parse_result (field: isMatch):**

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.check_sanctions(
        p_entity_name => 'Acme Trading LLC',
        p_entity_type => 'ORGANIZATION',
        p_country     => 'US'
    );

    -- Sanctions uses 'isMatch' — TRUE means a match was found (bad)
    l_result := qubiton_api_pkg.parse_result(
        p_json       => l_json,
        p_field_name => 'isMatch'
    );

    IF l_result.success AND l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('SANCTIONS MATCH FOUND — review required');
    ELSIF l_result.success AND NOT l_result.is_valid THEN
        DBMS_OUTPUT.PUT_LINE('No sanctions match — clear');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Screening error: ' || l_result.message);
    END IF;
END;
/
```

### 11. screen_pep

Screens for Politically Exposed Persons.

```sql
SELECT qubiton_api_pkg.screen_pep(
    p_entity_name => 'Jane Doe'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.screen_pep(
    p_entity_name   => 'Jane Doe',
    p_country       => 'US',
    p_date_of_birth => '1965-03-22'
) FROM DUAL;
```

### 12. check_directors

Checks for disqualified directors.

```sql
SELECT qubiton_api_pkg.check_directors(
    p_company_name => 'Acme Ltd',
    p_country      => 'GB'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.check_directors(
    p_company_name        => 'Acme Ltd',
    p_country             => 'GB',
    p_registration_number => '12345678'
) FROM DUAL;
```

---

## EPA

### 13. check_epa_prosecution

Checks for EPA enforcement actions.

```sql
SELECT qubiton_api_pkg.check_epa_prosecution(
    p_entity_name => 'Chemical Corp'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.check_epa_prosecution(
    p_entity_name => 'Chemical Corp',
    p_country     => 'US',
    p_state       => 'TX'
) FROM DUAL;
```

### 14. lookup_epa_prosecution

Returns detailed EPA prosecution records.

```sql
SELECT qubiton_api_pkg.lookup_epa_prosecution(
    p_entity_name => 'Chemical Corp'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_epa_prosecution(
    p_entity_name => 'Chemical Corp',
    p_country     => 'US',
    p_state       => 'TX'
) FROM DUAL;
```

---

## Healthcare

### 15. check_healthcare_exclusion

Checks if a healthcare entity is on exclusion lists.

```sql
SELECT qubiton_api_pkg.check_healthcare_exclusion(
    p_entity_name => 'Dr. John Smith'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.check_healthcare_exclusion(
    p_entity_name => 'Dr. John Smith',
    p_npi         => '1234567890',
    p_entity_type => 'INDIVIDUAL'
) FROM DUAL;
```

### 16. lookup_healthcare_exclusion

Returns detailed healthcare exclusion records.

```sql
SELECT qubiton_api_pkg.lookup_healthcare_exclusion(
    p_entity_name => 'Dr. John Smith'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_healthcare_exclusion(
    p_entity_name => 'Dr. John Smith',
    p_npi         => '1234567890',
    p_entity_type => 'INDIVIDUAL'
) FROM DUAL;
```

---

## Risk and Financial

### 17. check_bankruptcy_risk

Checks bankruptcy filings for a company.

```sql
SELECT qubiton_api_pkg.check_bankruptcy_risk(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.check_bankruptcy_risk(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

### 18. lookup_credit_score

Retrieves credit score for a company.

```sql
SELECT qubiton_api_pkg.lookup_credit_score(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_credit_score(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

### 19. lookup_fail_rate

Retrieves payment failure rate data.

```sql
SELECT qubiton_api_pkg.lookup_fail_rate(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_fail_rate(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

### 20. assess_entity_risk

Comprehensive entity risk assessment.

```sql
SELECT qubiton_api_pkg.assess_entity_risk(
    p_entity_name => 'Acme Corp',
    p_entity_type => 'ORGANIZATION',
    p_country     => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.assess_entity_risk(
    p_entity_name         => 'Acme Corp',
    p_entity_type         => 'ORGANIZATION',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

### 21. lookup_credit_analysis

Detailed credit analysis report.

```sql
SELECT qubiton_api_pkg.lookup_credit_analysis(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_credit_analysis(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

---

## ESG and Cybersecurity

### 22. lookup_esg_score

Retrieves ESG (Environmental, Social, Governance) scores.

```sql
SELECT qubiton_api_pkg.lookup_esg_score(
    p_company_name => 'Apple Inc'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_esg_score(
    p_company_name        => 'Apple Inc',
    p_country             => 'US',
    p_registration_number => '0000320193'
) FROM DUAL;
```

### 23. domain_security_report

Generates a cybersecurity report for a domain.

```sql
SELECT qubiton_api_pkg.domain_security_report(
    p_domain => 'example.com'
) FROM DUAL;
```

### 24. check_ip_quality

Assesses the quality/reputation of an IP address.

```sql
SELECT qubiton_api_pkg.check_ip_quality(
    p_ip_address => '8.8.8.8'
) FROM DUAL;
```

---

## Corporate Structure

### 25. lookup_beneficial_ownership

Looks up beneficial ownership information.

```sql
SELECT qubiton_api_pkg.lookup_beneficial_ownership(
    p_company_name => 'Acme Holdings Ltd',
    p_country      => 'GB'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_beneficial_ownership(
    p_company_name        => 'Acme Holdings Ltd',
    p_country             => 'GB',
    p_registration_number => '12345678'
) FROM DUAL;
```

### 26. lookup_corporate_hierarchy

Returns the corporate parent/subsidiary structure.

```sql
SELECT qubiton_api_pkg.lookup_corporate_hierarchy(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_corporate_hierarchy(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789',
    p_duns_number         => '123456789'
) FROM DUAL;
```

### 27. lookup_duns

Looks up a D-U-N-S number for a company.

```sql
SELECT qubiton_api_pkg.lookup_duns(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_duns(
    p_company_name => 'Acme Corp',
    p_country      => 'US',
    p_city         => 'New York',
    p_state        => 'NY',
    p_postal_code  => '10001'
) FROM DUAL;
```

### 28. lookup_hierarchy

Retrieves a corporate hierarchy tree from a D-U-N-S number.

```sql
SELECT qubiton_api_pkg.lookup_hierarchy(
    p_duns_number => '123456789'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_hierarchy(
    p_duns_number => '123456789',
    p_depth       => 5
) FROM DUAL;
```

---

## Industry

### 29. validate_npi

Validates a National Provider Identifier (US healthcare).

```sql
SELECT qubiton_api_pkg.validate_npi(
    p_npi => '1234567890'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_npi(
    p_npi         => '1234567890',
    p_entity_name => 'Dr. John Smith'
) FROM DUAL;
```

### 30. validate_medpass

Validates against the MedPASS database.

```sql
SELECT qubiton_api_pkg.validate_medpass(
    p_entity_name => 'Smith Medical Group'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_medpass(
    p_entity_name => 'Smith Medical Group',
    p_entity_type => 'ORGANIZATION',
    p_country     => 'US'
) FROM DUAL;
```

### 31. lookup_dot_carrier

Looks up a DOT motor carrier by number.

```sql
SELECT qubiton_api_pkg.lookup_dot_carrier(
    p_dot_number => '12345'
) FROM DUAL;
```

### 32. validate_india_identity

Validates Indian identity documents (PAN, Aadhaar, GSTIN, etc.).

```sql
SELECT qubiton_api_pkg.validate_india_identity(
    p_id_type   => 'PAN',
    p_id_number => 'ABCDE1234F'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_india_identity(
    p_id_type   => 'PAN',
    p_id_number => 'ABCDE1234F',
    p_name      => 'Rajesh Kumar'
) FROM DUAL;
```

---

## Certification

### 33. validate_certification

Validates a certification number.

```sql
SELECT qubiton_api_pkg.validate_certification(
    p_certification_number => 'MBE-2024-001',
    p_certification_type   => 'MBE'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.validate_certification(
    p_certification_number => 'MBE-2024-001',
    p_certification_type   => 'MBE',
    p_country              => 'US'
) FROM DUAL;
```

### 34. lookup_certification

Searches for certifications by company name.

```sql
SELECT qubiton_api_pkg.lookup_certification(
    p_company_name => 'Acme Corp'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_certification(
    p_company_name       => 'Acme Corp',
    p_certification_type => 'WBE',
    p_country            => 'US'
) FROM DUAL;
```

---

## Classification

### 35. lookup_business_classification

Looks up SIC/NAICS/UNSPSC classification codes.

```sql
SELECT qubiton_api_pkg.lookup_business_classification(
    p_company_name => 'Acme Corp',
    p_country      => 'US'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_business_classification(
    p_company_name        => 'Acme Corp',
    p_country             => 'US',
    p_registration_number => '12-3456789'
) FROM DUAL;
```

---

## Financial Ops

### 36. analyze_payment_terms

Analyzes and interprets payment terms text.

```sql
SELECT qubiton_api_pkg.analyze_payment_terms(
    p_terms_text => 'Net 30'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.analyze_payment_terms(
    p_terms_text     => '2/10 Net 30',
    p_currency       => 'USD',
    p_invoice_amount => 50000
) FROM DUAL;
```

### 37. lookup_exchange_rates

Retrieves currency exchange rates.

```sql
SELECT qubiton_api_pkg.lookup_exchange_rates(
    p_base_currency     => 'USD',
    p_target_currencies => 'EUR,GBP,JPY'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_exchange_rates(
    p_base_currency     => 'USD',
    p_target_currencies => 'EUR,GBP,JPY,CAD,AUD',
    p_date              => '2026-03-15'
) FROM DUAL;
```

---

## Supplier

### 38. lookup_ariba_supplier

Searches for suppliers in the SAP Business Network.

```sql
SELECT qubiton_api_pkg.lookup_ariba_supplier(
    p_company_name => 'Acme Corp'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.lookup_ariba_supplier(
    p_company_name => 'Acme Corp',
    p_country      => 'US',
    p_an_id        => 'AN01234567890'
) FROM DUAL;
```

### 39. validate_ariba_supplier

Validates an SAP Business Network ID.

```sql
SELECT qubiton_api_pkg.validate_ariba_supplier(
    p_an_id => 'AN01234567890'
) FROM DUAL;
```

---

## Gender

### 40. identify_gender

Identifies likely gender from a given name.

```sql
SELECT qubiton_api_pkg.identify_gender(
    p_name => 'Andrea'
) FROM DUAL;
```

Full call:

```sql
SELECT qubiton_api_pkg.identify_gender(
    p_name    => 'Andrea',
    p_country => 'IT'
) FROM DUAL;
```

---

## Reference

### 41. get_supported_tax_formats

Returns all supported tax ID formats by country (GET endpoint, no parameters).

```sql
SELECT qubiton_api_pkg.get_supported_tax_formats() FROM DUAL;
```

### 42. get_peppol_schemes

Returns all supported Peppol scheme identifiers (GET endpoint, no parameters).

```sql
SELECT qubiton_api_pkg.get_peppol_schemes() FROM DUAL;
```

---

## Bulk Processing Pattern

For validating multiple records, use a cursor loop with error handling:

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
    l_valid  PLS_INTEGER := 0;
    l_invalid PLS_INTEGER := 0;
    l_error  PLS_INTEGER := 0;
BEGIN
    FOR rec IN (
        SELECT vendor_id, tax_reference, country
        FROM   ap_suppliers
        WHERE  enabled_flag = 'Y'
        AND    ROWNUM <= 100  -- Process in batches
    ) LOOP
        BEGIN
            l_json := qubiton_api_pkg.validate_tax(
                p_tax_id  => rec.tax_reference,
                p_country => rec.country
            );

            l_result := qubiton_api_pkg.parse_result(l_json);

            IF l_result.success AND l_result.is_valid THEN
                l_valid := l_valid + 1;
            ELSE
                l_invalid := l_invalid + 1;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                l_error := l_error + 1;
                -- Continue processing remaining records
        END;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Valid: '   || l_valid);
    DBMS_OUTPUT.PUT_LINE('Invalid: ' || l_invalid);
    DBMS_OUTPUT.PUT_LINE('Errors: '  || l_error);
END;
/
```

## Using the Layer 2 Orchestrator

For EBS-integrated validation, use `qubiton_validate_pkg` which reads configuration from `QUBITON_VALIDATION_CFG`:

```sql
DECLARE
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_validate_pkg.validate_supplier_all(
        p_module_name    => 'AP_SUPPLIERS',
        p_vendor_id      => 12345,
        p_vendor_name    => 'Acme Corp',
        p_country        => 'US',
        p_tax_id         => '12-3456789',
        p_address_line1  => '123 Main St',
        p_city           => 'Springfield',
        p_state          => 'IL',
        p_postal_code    => '62701',
        p_account_number => '1234567890',
        p_routing_number => '021000021'
    );

    IF l_ok THEN
        DBMS_OUTPUT.PUT_LINE('All validations passed');
    ELSE
        DBMS_OUTPUT.PUT_LINE('One or more validations blocked — check QUBITON_API_LOG');
    END IF;
END;
/
```
