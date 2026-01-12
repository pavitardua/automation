-- CHANGED QUERY TO ALL ACTIVE SEASON ACROSS COACHSPAN LOOKING AT PAST ONE WEEK

--OrgName	OrgStatus	ProgramName	SeasonShortName	Activation Date	FPD	End	Active Season?	
--Associations	Change in last Day	% Change in last Day	
--Reg Forms Req/Prov	Reg Forms Provided	% Provided	Change in last Day	% Change in last Day	Reg Forms Outstanding	% Outstanding	
--BGC Forms Req/Prov	BGC Forms Provided	% Provided	Change in last Day	% Change in last Day	BGC Forms Outstanding	% Outstanding	
--Course Assignments	Courses Completed	% Completed	Change in last Day	% Change in last Day	Courses Outstanding	% Outstanding


-- Parameter for the report date (in Eastern Time)
DECLARE @ReportDate DATE = '2026-01-11';  -- Change this date as needed

-- Calculate Eastern Time boundaries for the specified date
DECLARE @DayStartET DATETIME, @DayEndET DATETIME;
SET @DayStartET = DATEADD(SECOND, -1, DATEADD(DAY, -7, CAST(@ReportDate AS DATETIME)));
SET @DayEndET = CAST(@ReportDate AS DATETIME);



-- Convert Eastern Time boundaries to UTC for database comparison
-- (Assuming your database stores timestamps in UTC)
DECLARE @DayStartUTC DATETIME, @DayEndUTC DATETIME;
SET @DayStartUTC = @DayStartET AT TIME ZONE 'Eastern Standard Time' AT TIME ZONE 'UTC';
SET @DayEndUTC = @DayEndET AT TIME ZONE 'Eastern Standard Time' AT TIME ZONE 'UTC';

WITH FirstPersonObjectRole AS (
			    SELECT *,
			           ROW_NUMBER() OVER (
			               PARTITION BY memberId 
			               ORDER BY PersonObjectRoleId
			           ) AS rn
			    FROM AlphaContact.dbo.PersonObjectRole
			    WHERE deletedFlag=0
			)
SELECT 
    'Report for (UTC): ' + 
    FORMAT(@DayStartUTC, 'MM/dd/yyyy HH:mm:ss') + ' to ' + 
    FORMAT(@DayEndUTC, 'MM/dd/yyyy HH:mm:ss') AS 'Report Period'

,l.name league_name,org.OrgId,orgStatus ,org.OrgName,prog.id programId,prog.defaultOnBoardingCoachStatusNumber DEFAULTONBOARD,
prog.includeBGCModule BGC, prog.automatedBackgroundCheckReminders BGCREMIND ,prog.includeRegistrationModule REG,prog.automatedRegistrationReminders REGREMIND,
prog.includeTrainingModule TRAIN,prog.automatedTrainingReminders TRAINREMIND,
prog.name ProgramName, los.name LOS, los.id  , 'https://go.coachspan.com/coach_entry/program/'+prog.urlFriendlyName CEE_link, 
s.SeasonId,s.SeasonShortName,
od.FirstName OD_First_Name ,od.LastName OD_Last_Name, OD_Email_Address,OD_contact_number

-- Associations (cumulative up to report date, with daily activity)
,associations.total_associations AS cumulative_associations
,associations.total_associations_last_day AS new_associations_today
,associations.percent_total_associations_last_day AS percent_new_associations

-- Registration metrics
,CAST((reg_outstanding.total_reg_outstanding * 100.0 / NULLIF(reg_requirements.total_reg_requirements, 0)) AS DECIMAL(10,2)) AS percent_reg_outstanding
,reg_requirements.total_reg_requirements AS total_reg_required
,reg_outstanding.total_reg_outstanding AS reg_still_outstanding
,reg_submissions.total_reg_submissions AS cumulative_reg_submissions
,reg_submissions.total_reg_submissions_last_day AS new_reg_submissions_today
,reg_submissions.percent_total_reg_submissions_last_day AS percent_new_reg_submissions

-- Background Check metrics
,CAST((bgc_outstanding.total_bgc_outstanding * 100.0 / NULLIF(bgc_requirements.total_bgc_requirements, 0)) AS DECIMAL(10,2)) AS percent_bgc_outstanding
,bgc_requirements.total_bgc_requirements AS total_bgc_required
,bgc_outstanding.total_bgc_outstanding AS bgc_still_outstanding
,bgc_submissions.total_bgc_submissions AS cumulative_bgc_submissions
,bgc_submissions.total_bgc_submissions_last_day AS new_bgc_submissions_today
,bgc_submissions.percent_total_bgc_submissions_last_day AS percent_new_bgc_submissions

-- Training metrics
,training_completions.total_training_completions AS cumulative_training_completions
,training_completions.total_training_completions_last_day AS new_training_completions_today
,training_completions.percent_total_training_completions_last_day AS percent_new_training_completions

-- Email activities on report date

 ,ISNULL(EMAIL_LOGS.TRAINING_REMINDERS_SENT, 0) AS training_reminders_sent_today
,ISNULL(EMAIL_LOGS.REG_REMINDERS_SENT, 0) AS reg_reminders_sent_today
,ISNULL(EMAIL_LOGS.BGC_REMINDERS_SENT, 0) AS bgc_reminders_sent_today
,ISNULL(EMAIL_LOGS.VERIFICATION_CODES_SENT, 0) AS verification_codes_sent_today
,ISNULL(EMAIL_LOGS.CONTENT_PACKAGES_SENT, 0) AS content_packages_sent_today
 

FROM AlphaProgramReg.dbo.Program prog
JOIN AlphaDesign.dbo.Season s ON s.programId=prog.id 
JOIN AlphaProgramReg.dbo.ProgramSubscriptionLOS psl on psl.programId =prog.id AND psl.isActive =1
JOIN AlphaProgramReg.dbo.LevelOfService los on psl.levelOfServiceId =los.id 
LEFT JOIN AlphaProgramReg.dbo.League l ON prog.leagueId = l.id 
JOIN AlphaContact.dbo.Organization org ON prog.orgId = org.OrgId 

-- Organization Director contact info
LEFT JOIN (
    SELECT FirstName,LastName,MappedObjectId,p.PersonId 
    FROM AlphaContact.dbo.PersonObjectRole por 
    JOIN AlphaContact.dbo.Person p ON p.PersonId = por.PersonId
    WHERE RoleId = 'OD' AND DeletedFlag = 0
) od ON od.MappedObjectId = org.OrgId
LEFT JOIN (
    SELECT ContactValue AS OD_Email_Address, PersonId
    FROM AlphaContact.dbo.ContactMethod cm  
    WHERE cm.ContactTypeId = 'PEML' AND cm.ActiveFlag = 1
) od_email ON od_email.PersonId = od.PersonId
LEFT JOIN (
    SELECT string_agg(CAST(ContactValue  AS varchar(max)), ', ') AS OD_contact_number, PersonId
    FROM AlphaContact.dbo.ContactMethod cm 
    WHERE cm.ContactTypeId IN ('HMFON','WKFON','CLFON','OFON') AND cm.ActiveFlag = 1
    GROUP BY PersonId
) OD_phone ON OD_phone.PersonId = od.PersonId

-- Associations (cumulative up to report date)
LEFT JOIN (
    SELECT 
        COUNT(*) AS total_associations,  -- Cumulative up to report date
        COUNT(CASE WHEN porAssoc.DateCreated >= @DayStartUTC
                    AND porAssoc.DateCreated <= @DayEndUTC
                   THEN 1 END) AS total_associations_last_day,  -- On report date
        CAST(
            COUNT(CASE WHEN porAssoc.DateCreated >= @DayStartUTC
                        AND porAssoc.DateCreated <= @DayEndUTC
                       THEN 1 END) * 100.0 / 
            NULLIF(COUNT(*), 0) 
            AS DECIMAL(10,2)
        ) AS percent_total_associations_last_day,
        s.seasonId, s.programId
    FROM AlphaContact.dbo.PersonObjectRole porAssoc 
    JOIN AlphaDesign.dbo.Division d ON d.DivisionId = porAssoc.MappedObjectId
    JOIN AlphaDesign.dbo.Season s ON s.SeasonId = d.SeasonId
    WHERE (RoleId = 'HC' OR RoleId = 'AC') 
      AND porAssoc.DeletedFlag = 0
      --AND porAssoc.DateCreated >= @DayStartUTC 
      AND porAssoc.DateCreated <= @DayEndUTC  -- Only count up to report date
    GROUP BY s.seasonId, s.programId
) associations ON associations.seasonId = s.SeasonId 

-- Registration Submissions (cumulative up to report date)
LEFT JOIN (
    SELECT 
        COUNT(*) AS total_reg_submissions,  -- Cumulative up to report date
        COUNT(CASE WHEN reg.submittedDate >= @DayStartUTC
                    AND reg.submittedDate <= @DayEndUTC
                   THEN 1 END) AS total_reg_submissions_last_day,  -- On report date
        CAST(
            COUNT(CASE WHEN reg.submittedDate >= @DayStartUTC
                        AND reg.submittedDate <= @DayEndUTC
                       THEN 1 END) * 100.0 / 
            NULLIF(COUNT(*), 0) 
            AS DECIMAL(10,2)
        ) AS percent_total_reg_submissions_last_day,
        reg.seasonId, reg.programId
    FROM AlphaProgramReg.dbo.Registration reg 
    WHERE reg.submittedDate IS NOT NULL 
      AND reg.active = 1
      --AND reg.submittedDate >= @DayStartUTC 
      AND reg.submittedDate <= @DayEndUTC  -- Only count up to report date
    GROUP BY reg.seasonId, reg.programId
) reg_submissions ON reg_submissions.seasonId = s.SeasonId  

-- Registration Outstanding (as of report date)
-- Only count registrations created on or before report date that are still outstanding
LEFT JOIN (
    SELECT COUNT(*) AS total_reg_outstanding, seasonId, programId
    FROM AlphaProgramReg.dbo.Registration reg 
    WHERE reg.registrationStatus  NOT IN ('Provided','Provided_HardCopy','Completed_Previously') 
      AND reg.active = 1
      AND reg.createdDate >= @DayStartUTC 
      AND reg.createdDate <= @DayEndUTC  -- Only registrations created on or before report date
      AND reg.submittedDate IS NULL
    GROUP BY reg.seasonId, reg.programId
) reg_outstanding ON reg_outstanding.seasonId = s.SeasonId 

-- BGC Outstanding (as of report date)
LEFT JOIN (
    SELECT COUNT(*) AS total_bgc_outstanding, seasonId, programId
    FROM AlphaProgramReg.dbo.Registration reg 
    WHERE reg.bgcStatus NOT IN ('PROVIDED','PROVIDED_HARDCOPY','COMPLETED_PREVIOUSLY')  
      AND reg.bgcActive = 1
      AND reg.createdDate >= @DayStartUTC AND reg.createdDate <= @DayEndUTC  -- Only registrations created on or before report date
      
      AND reg.bgcSubmittedDate IS NULL 
    GROUP BY reg.seasonId, reg.programId
) bgc_outstanding ON bgc_outstanding.seasonId = s.SeasonId 

-- Total Registration Requirements (as of report date)
-- Only count active registrations created on or before report date
LEFT JOIN (
    SELECT COUNT(*) AS total_reg_requirements, seasonId, programId
    FROM AlphaProgramReg.dbo.Registration reg 
    WHERE reg.active = 1
      AND reg.createdDate >= @DayStartUTC AND reg.createdDate <= @DayEndUTC  -- Only registrations created on or before report date
    GROUP BY reg.seasonId, reg.programId
) reg_requirements ON reg_requirements.seasonId = s.SeasonId 

-- Total BGC Requirements (as of report date)
LEFT JOIN (
    SELECT COUNT(*) AS total_bgc_requirements, seasonId, programId
    FROM AlphaProgramReg.dbo.Registration reg 
    WHERE reg.bgcActive = 1
      AND reg.createdDate >= @DayStartUTC AND reg.createdDate <= @DayEndUTC  -- Only registrations created on or before report date
    GROUP BY reg.seasonId, reg.programId
) bgc_requirements ON bgc_requirements.seasonId = s.SeasonId 

-- BGC Submissions (cumulative up to report date)
LEFT JOIN (
    SELECT 
        COUNT(*) AS total_bgc_submissions,  -- Cumulative up to report date
        COUNT(CASE WHEN bgc.bgcSubmittedDate >= @DayStartUTC
                    AND bgc.bgcSubmittedDate <= @DayEndUTC
                   THEN 1 END) AS total_bgc_submissions_last_day,  -- On report date
        CAST(
            COUNT(CASE WHEN bgc.bgcSubmittedDate >= @DayStartUTC
                        AND bgc.bgcSubmittedDate <= @DayEndUTC
                       THEN 1 END) * 100.0 / 
            NULLIF(COUNT(*), 0) 
            AS DECIMAL(10,2)
        ) AS percent_total_bgc_submissions_last_day,
        bgc.seasonId, bgc.programId
    FROM AlphaProgramReg.dbo.Registration bgc 
    WHERE bgc.bgcSubmittedDate IS NOT NULL 
      AND bgc.bgcActive = 1
      --AND bgc.bgcSubmittedDate >= @DayStartUTC 
      AND bgc.bgcSubmittedDate <= @DayEndUTC  -- Only count up to report date
    GROUP BY bgc.seasonId, bgc.programId
) bgc_submissions ON bgc_submissions.seasonId = s.SeasonId 

-- Training Completions (cumulative up to report date)
LEFT JOIN (
    SELECT 
        COUNT(*) AS total_training_completions,  -- Cumulative up to report date
        COUNT(CASE WHEN CC.OverallDateCompleted >= @DayStartUTC
                    AND CC.OverallDateCompleted <= @DayEndUTC
                   THEN 1 END) AS total_training_completions_last_day,  -- On report date
        CAST(
            COUNT(CASE WHEN CC.OverallDateCompleted >= @DayStartUTC
                        AND CC.OverallDateCompleted <= @DayEndUTC
                       THEN 1 END) * 100.0 / 
            NULLIF(COUNT(*), 0) 
            AS DECIMAL(10,2)
        ) AS percent_total_training_completions_last_day,
        SA.seasonId
    FROM AlphaTraining.dbo.CoachClass CC 
    JOIN AlphaTraining.dbo.SeasonAssignment SA ON SA.SeasonAssignId = CC.SeasonAssignId  
    WHERE CC.CourseId IN (52,53,54,55) 
      AND CC.OverallStatusId LIKE 'C'
      --AND CC.OverallDateCompleted >= @DayStartUTC
      AND CC.OverallDateCompleted <= @DayEndUTC  -- Only count up to report date
    GROUP BY SA.seasonId
) training_completions ON training_completions.seasonId = s.SeasonId 

-- Email Activities on report date

 LEFT JOIN (
 	
    SELECT o.OrgId, s2.seasonId,
           SUM(CASE WHEN el.emailType = 'TRAINING_REMINDER' THEN 1 ELSE 0 END) AS TRAINING_REMINDERS_SENT,
           SUM(CASE WHEN el.emailType = 'REG_REMINDER' THEN 1 ELSE 0 END) AS REG_REMINDERS_SENT,
           SUM(CASE WHEN el.emailType = 'BGC_REMINDER' THEN 1 ELSE 0 END) AS BGC_REMINDERS_SENT,
           SUM(CASE WHEN el.emailType = 'VERIFICATION_CODE' THEN 1 ELSE 0 END) AS VERIFICATION_CODES_SENT,
           SUM(CASE WHEN el.emailType = 'CONTENT_PACKAGES' THEN 1 ELSE 0 END) AS CONTENT_PACKAGES_SENT
     
    FROM AlphaContact.dbo.EmailLog el
    INNER JOIN AlphaContact.dbo.ContactMethod CM1 ON CM1.ContactValue =el.toEmail AND (CM1.ContactTypeId = 'PEML' OR CM1.ContactTypeId = 'ATEML')
	--INNER JOIN AlphaContact.dbo.Account a ON a.LoginUserName = el.toEmail 
    INNER JOIN AlphaContact.dbo.OrgMember om ON om.PersonId  = CM1.PersonId  
    INNER JOIN FirstPersonObjectRole AS POR ON POR.memberId=om.OrgMemberId AND POR.RoleId IN ('HC','AC')
    INNER JOIN AlphaDesign.dbo.Division d2 ON d2.divisionId= por.MappedObjectId
    INNER JOIN AlphaDesign.dbo.Season s2 ON  d2.seasonId=s2.seasonId
    
    INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId = om.OrgId 
    
    
    
    
    WHERE el.emailType IN ('TRAINING_REMINDER', 'REG_REMINDER', 'BGC_REMINDER', 'VERIFICATION_CODE','CONTENT_PACKAGES')
      AND el.dateCreated >= @DayStartUTC
      AND el.dateCreated <= @DayEndUTC  -- Only emails sent on report date
      AND CM1.ContactValue =el.toEmail 
    GROUP BY o.OrgId,s2.seasonId
) AS EMAIL_LOGS ON EMAIL_LOGS.OrgId = org.OrgId AND EMAIL_LOGS.seasonId =  s.seasonId


 

WHERE 1=1 --AND  S.seasonid=1158 
 AND s.DefaultEndDate>=GETDATE()
 --AND prog.leagueId IS NOT NULL 
 --AND prog.leagueId IN (1,2) 
ORDER BY orgname,reg_outstanding.total_reg_outstanding DESC; 
