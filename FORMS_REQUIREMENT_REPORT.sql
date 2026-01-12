--------------------------------------------------------------------------------------------------------------------
-- COMPREHENSIVE REGISTRATION STATUS REPORT
-- Purpose: Detailed overview of coach registration forms with module status and timestamps
-- Scope: All seasons (SeasonId < 10000) with Eastern Time conversion
-- Includes: Registration, Background Check, and Training module statuses
-- Note: LEFT JOIN on Account table to include registrations without associated accounts
--------------------------------------------------------------------------------------------------------------------
--SELECT DISTINCT ProgramName,SeasonShortName,OrgName,COUNT(*) FROM (

WITH FormsRecordRowNumberAllocator AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY memberId, seasonId 
               ORDER BY lastModifiedDate  DESC, id DESC
           ) AS rn
    FROM AlphaProgramReg.dbo.Registration
)
SELECT *
FROM (
SELECT 
	
    -- Timestamp Information (Eastern Time)
    CAST(r.lastModifiedDate AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS DATETIME) AS 'LastModifiedDateEastern',
    
    -- Coach Experience and Organization Details
    r.coachYouthOrgBefore,
    o.OrgName,
    O.orgStatus AS OrgStatus,
    
    -- Program and Season Information
    prog.name AS ProgramName,
    s.SeasonShortName,
    s.ActivationDate,
    s.DefaultStartDate AS 'FPD',  -- First Program Date
    s.DefaultEndDate AS 'End',
    
    -- Season Activation Status
    CASE 
        WHEN GETDATE() > s.DefaultEndDate THEN 'EXPIRED' 
        ELSE 'Active' 
    END AS 'Activation Season?',
    
    -- Member/Coach Personal Information
    om.OrgMemberId AS 'Member Id',
    p.FirstName AS 'Member First Name',
    p.LastName AS 'Member Last Name',
    a.LoginUserName AS 'Member Email',
    a.LoginVerifiedFlag,
    a.lastLoginDate,
    
    -- REGISTRATION MODULE STATUS
    prog.includeRegistrationModule AS 'REG mod',
    prog.automatedRegistrationReminders AS 'REG reminders',
    r.registrationStatus AS 'REG Status',
    r.active AS 'REG Active',
    CAST(r.submittedDate AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS DATETIME) AS 'REG submittedDate Eastern',
    r.acknowledgementAccepted,
    r.signedFirstName,
    r.signedLastName,
    r.hardCopyProvided,
    
    -- BACKGROUND CHECK MODULE STATUS
    prog.includeBGCModule AS 'BGC mod',
    prog.automatedBackgroundCheckReminders AS 'BGC reminders',
    r.bgcStatus AS 'BGC Status',
    r.bgcActive AS 'BGC Active',
    CAST(r.bgcSubmittedDate AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS DATETIME) AS 'BGC submittedDate Eastern',
    r.backgroundCheckAckAccepted,
    r.backgroundCheckAckFirstName,
    r.backgroundCheckAckLastName,
    
    -- SYSTEM AND MIGRATION FIELDS
    r.migrationStatus,
    r.createdDate,
    CAST(r.createdDate AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS DATETIME) AS 'REG createdDate Eastern',
    
    -- Registration Form Identifiers and Versioning
    r.id AS registrationFormId,
    r.originallySubmittedRegistrationId,
    r.originallySubmittedBgcFormId,
    r.orgStandardBgcProgramRevisionVersion,
    r.orgStandardProgramRevisionVersion,

    
    -- TRAINING MODULE CONFIGURATION
    prog.includeTrainingModule AS 'TRAIN mod',
    prog.automatedTrainingReminders AS 'TRAIN reminders',
    
    -- FRNA
    rn,
    (CASE 
        WHEN rn = 1 AND r.active = 1 THEN 'LATEST_ACTIVE'
        WHEN rn = 1 AND r.active = 0 THEN 'LATEST_INACTIVE'
        WHEN rn > 1 AND r.active = 1 THEN 'OLD_ACTIVE_ANOMALY'
        ELSE 'HISTORICAL'
    END) AS 'regStatusDupIndicator',
    
    (CASE 
        WHEN rn = 1 AND r.bgcActive = 1 THEN 'LATEST_ACTIVE'
        WHEN rn = 1 AND r.bgcActive = 0 THEN 'LATEST_INACTIVE'
        WHEN rn > 1 AND r.bgcActive = 1 THEN 'OLD_ACTIVE_ANOMALY'
        ELSE 'HISTORICAL'
    END) AS 'bgcStatusDupIndicator'

FROM AlphaProgramReg.dbo.Registration r 
join FormsRecordRowNumberAllocator FRNA ON r.id=FRNA.id

-- Program and Season Relationships
JOIN AlphaProgramReg.dbo.Program prog ON prog.id = r.programId
JOIN AlphaDesign.dbo.Season s ON s.SeasonId = r.seasonId 

-- Member and Personal Information Relationships
JOIN AlphaContact.dbo.OrgMember om ON om.OrgMemberId = r.memberId
JOIN AlphaContact.dbo.Person p ON p.PersonId = om.PersonId 

-- Account Information (LEFT JOIN to include registrations without accounts)
LEFT JOIN AlphaContact.dbo.Account a ON a.PersonId = p.PersonId 

-- Organization Relationship
JOIN AlphaContact.dbo.Organization o ON o.OrgId = prog.orgId 

-- Filter: Exclude test seasons (SeasonId >= 10000)
WHERE s.seasonId < 10000 
--AND r.seasonId IN (1025,
--1046,
--1050,
--1051,
--1058,
--1062,
--1069,
--1078,
--1079,
--1083,
--1086,
--1095,
--1102,
--1110,
--1112,
--1116,
--1132,
--1136,
--1138,
--1142,
--1148)
--AND r.bgcActive=0 AND r.lastModifiedDate >= DATEADD(DAY, -1, GETDATE())
--AND r.programId=1646 AND r.memberId=17252 -- TODD GEBSKI SHOULD BE MARKED AS REQUIRED
--AND r.programId=1825 AND r.memberId=17547 -- BRONZE TEST SHOULD BE CREATED WITH REG REQUIRED< BGC STATUS SHOULD NOT BE NULL and BGC ACTIVE SHOULD BE FALSE CL4S SHOULD WORK 
--) AS C GROUP BY ProgramName,SeasonShortName,OrgName
-- Order by most recently modified registrations first
--AND r.memberId=17191
--AND rn>2 --17191,13893
) AS subquery
--WHERE regStatusDupIndicator='OLD_ACTIVE_ANOMALY' OR bgcStatusDupIndicator='OLD_ACTIVE_ANOMALY'
ORDER BY LastModifiedDateEastern DESC;
