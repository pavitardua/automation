

--OrgName	OrgStatus	ProgramName	SeasonShortName	Activation Date	FPD	End	Active Season?	
--Associations	Change in last Day	% Change in last Day	
--Reg Forms Req/Prov	Reg Forms Provided	% Provided	Change in last Day	% Change in last Day	Reg Forms Outstanding	% Outstanding	
--BGC Forms Req/Prov	BGC Forms Provided	% Provided	Change in last Day	% Change in last Day	BGC Forms Outstanding	% Outstanding	
--Course Assignments	Courses Completed	% Completed	Change in last Day	% Change in last Day	Courses Outstanding	% Outstanding


SELECT CAST(DATEADD(DAY, -1, GETDATE()) AT TIME ZONE 'UTC' AT TIME ZONE 'Eastern Standard Time' AS DATETIME) AS 'LastDay'

,l.name league_name,org.OrgId,orgStatus ,org.OrgName,prog.id programId,prog.defaultOnBoardingCoachStatusNumber DEFAULTONBOARD,
prog.includeBGCModule BGC, prog.automatedBackgroundCheckReminders BGCREMIND ,prog.includeRegistrationModule REG,prog.automatedRegistrationReminders REGREMIND,
prog.includeTrainingModule TRAIN,prog.automatedTrainingReminders TRAINREMIND,
prog.name ProgramName, los.name LOS, los.id  , 'https://go.coachspan.com/coach_entry/program/'+prog.urlFriendlyName CEE_link, 
s.SeasonId,s.SeasonShortName,
od.FirstName OD_First_Name ,od.LastName OD_Last_Name, OD_Email_Address,OD_contact_number


,associations.total_associations,associations.total_associations_last_day,percent_total_associations_last_day

,CAST((reg_outstanding.total_reg_outstanding * 100.0 / NULLIF(reg_requirements.total_reg_requirements, 0)) AS DECIMAL(10,2)) AS percent_reg_outstanding
,reg_requirements.total_reg_requirements,reg_outstanding.total_reg_outstanding
,reg_submissions.total_reg_submissions,reg_submissions.total_reg_submissions_last_day,reg_submissions.percent_total_reg_submissions_last_day

,CAST((bgc_outstanding.total_bgc_outstanding * 100.0 / NULLIF(bgc_requirements.total_bgc_requirements, 0)) AS DECIMAL(10,2)) AS percent_bgc_outstanding
,bgc_requirements.total_bgc_requirements,bgc_outstanding.total_bgc_outstanding
,bgc_submissions.total_bgc_submissions,bgc_submissions.total_bgc_submissions_last_day,bgc_submissions.percent_total_bgc_submissions_last_day




,training_completions.total_training_completions,training_completions.total_training_completions_last_day,training_completions.percent_total_training_completions_last_day

,TRAINING_REMINDERS.TRAINING_REMINDERS_SENT
,REG_REMINDERS.REG_REMINDERS_SENT
,BGC_REMINDERS.BGC_REMINDERS_SENT
,VERIFICATION_CODES.VERIFICATION_CODES_SENT

--,pd.FirstName PD_First_Name,pd.LastName PD_Last_Name,pd_contact_info.contact_info pd_contact_info
FROM AlphaProgramReg.dbo.Program prog
JOIN AlphaDesign.dbo.Season s ON s.programId=prog.id AND YEAR(s.DefaultStartDate)=2025 AND MONTH(s.DefaultStartDate) IN (9,10,11)
JOIN AlphaProgramReg.dbo.ProgramSubscriptionLOS psl on psl.programId =prog.id AND psl.isActive =1
JOIN AlphaProgramReg.dbo.LevelOfService los on psl.levelOfServiceId =los.id 
JOIN AlphaProgramReg.dbo.League l ON prog.leagueId = l.id 
JOIN AlphaContact.dbo.Organization org ON prog.orgId = org.OrgId 
LEFT JOIN (
SELECT FirstName,LastName,MappedObjectId,p.PersonId FROM AlphaContact.dbo.PersonObjectRole por 
JOIN AlphaContact.dbo.Person p ON p.PersonId = por.PersonId
WHERE RoleId = 'OD' AND DeletedFlag = 0
) od ON od.MappedObjectId = org.OrgId
LEFT JOIN (
SELECT ContactValue AS OD_Email_Address,cm.PersonId,ActiveFlag FROM AlphaContact.dbo.ContactMethod cm  
WHERE cm.ContactTypeId = ('PEML')
GROUP BY ActiveFlag ,PersonId,ContactValue
HAVING cm.ActiveFlag = 1
) od_email ON od_email.PersonId = od.PersonId
LEFT JOIN (
SELECT string_agg(CAST(ContactValue  AS varchar(max)), ', ') OD_contact_number,cm.PersonId,ActiveFlag FROM AlphaContact.dbo.ContactMethod cm 
WHERE cm.ContactTypeId IN ('HMFON','WKFON','CLFON','OFON')
GROUP BY ActiveFlag ,PersonId
HAVING cm.ActiveFlag = 1 
) OD_phone ON OD_phone.PersonId = od.PersonId

LEFT JOIN (
SELECT COUNT(*) AS total_associations,
COUNT(CASE 
          WHEN porAssoc.DateCreated  >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) AS total_associations_last_day
          ,  CAST(
    COUNT(CASE 
          WHEN porAssoc.DateCreated >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) * 100.0 / NULLIF(COUNT(*), 0) 
    AS DECIMAL(10,2)
)  AS percent_total_associations_last_day
          ,s.seasonId,s.programId
FROM AlphaContact.dbo.PersonObjectRole porAssoc 

JOIN AlphaDesign.dbo.Division d ON d.DivisionId=porAssoc.MappedObjectId
JOIN AlphaDesign.dbo.Season s ON s.SeasonId =d.SeasonId
WHERE RoleId = 'HC' OR  RoleId = 'AC' AND porAssoc.DeletedFlag =0
GROUP BY s.seasonId,s.programId
) associations ON associations.seasonId = s.SeasonId 

LEFT JOIN (
SELECT COUNT(*) AS total_reg_submissions,
COUNT(CASE 
          WHEN reg.submittedDate  >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) AS total_reg_submissions_last_day
          , CAST(
    COUNT(CASE 
          WHEN reg.submittedDate >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) * 100.0 / NULLIF(COUNT(*), 0) 
    AS DECIMAL(10,2)
) AS percent_total_reg_submissions_last_day
          ,reg.seasonId,reg.programId
FROM AlphaProgramReg.dbo.Registration reg WHERE reg.submittedDate IS NOT NULL AND reg.active=1
GROUP BY reg.seasonId ,reg.programId
) reg_submissions ON reg_submissions.seasonId = s.SeasonId 

LEFT JOIN (
SELECT COUNT(*) AS total_reg_outstanding
          ,reg.seasonId,reg.programId
FROM AlphaProgramReg.dbo.Registration reg WHERE reg.registrationStatus IN('Required','Drafted') AND reg.active=1
GROUP BY reg.seasonId ,reg.programId
) reg_outstanding ON reg_outstanding.seasonId = s.SeasonId 

LEFT JOIN (
SELECT COUNT(*) AS total_bgc_outstanding
          ,reg.seasonId,reg.programId
FROM AlphaProgramReg.dbo.Registration reg WHERE reg.bgcStatus  IN('REQUIRED','DRAFTED') AND reg.bgcActive =1
GROUP BY reg.seasonId ,reg.programId
) bgc_outstanding ON bgc_outstanding.seasonId = s.SeasonId 


LEFT JOIN (
SELECT COUNT(*) AS total_reg_requirements
          ,reg.seasonId,reg.programId
FROM AlphaProgramReg.dbo.Registration reg WHERE reg.active =1
GROUP BY reg.seasonId ,reg.programId
) reg_requirements ON reg_requirements.seasonId = s.SeasonId 

LEFT JOIN (
SELECT COUNT(*) AS total_bgc_requirements
          ,reg.seasonId,reg.programId
FROM AlphaProgramReg.dbo.Registration reg WHERE reg.bgcActive  =1
GROUP BY reg.seasonId ,reg.programId
) bgc_requirements ON bgc_requirements.seasonId = s.SeasonId 

LEFT JOIN (
SELECT COUNT(*) AS total_bgc_submissions,
COUNT(CASE 
          WHEN bgc.bgcSubmittedDate  >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) AS total_bgc_submissions_last_day
          , CAST(
    COUNT(CASE 
          WHEN bgc.bgcSubmittedDate >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) * 100.0 / NULLIF(COUNT(*), 0) 
    AS DECIMAL(10,2)
) AS percent_total_bgc_submissions_last_day
          ,bgc.seasonId,bgc.programId
FROM AlphaProgramReg.dbo.Registration bgc WHERE bgc.bgcSubmittedDate IS NOT NULL AND bgc.bgcActive =1
GROUP BY bgc.seasonId ,bgc.programId
) bgc_submissions ON bgc_submissions.seasonId = s.SeasonId 


LEFT JOIN (
SELECT COUNT(*) AS total_training_completions,
COUNT(CASE 
          WHEN CC.OverallDateCompleted   >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) AS total_training_completions_last_day
          , CAST(
    COUNT(CASE 
          WHEN CC.OverallDateCompleted  >= DATEADD(DAY, -1, GETDATE()) 
          THEN 1 
          END) * 100.0 / NULLIF(COUNT(*), 0) 
    AS DECIMAL(10,2)
) AS percent_total_training_completions_last_day
          ,SA.seasonId
FROM AlphaTraining.dbo.CoachClass CC 
JOIN AlphaTraining.dbo.SeasonAssignment SA ON SA.SeasonAssignId =CC.SeasonAssignId  
WHERE CC.CourseId IN (52,53,54,55) AND CC.OverallStatusId LIKE 'C%'
GROUP BY SA.seasonId 
--ORDER BY total_training_completions_last_day DESC
) training_completions ON training_completions.seasonId = s.SeasonId 

LEFT JOIN (
	Select  COUNT(*) TRAINING_REMINDERS_SENT, el.emailType, o.OrgId  
	FROM AlphaContact.dbo.EmailLog el
	LEFT JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
	INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
	INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
	INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
	WHERE el.emailType ='TRAINING_REMINDER' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
	GROUP BY o.OrgId, emailType

) AS TRAINING_REMINDERS ON TRAINING_REMINDERS.OrgId=org.OrgId


LEFT JOIN (
	Select  COUNT(*) REG_REMINDERS_SENT, el.emailType, o.OrgId  
	FROM AlphaContact.dbo.EmailLog el
	LEFT JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
	INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
	INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
	INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
	WHERE el.emailType ='REG_REMINDER' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
	GROUP BY o.OrgId, emailType

) AS REG_REMINDERS ON REG_REMINDERS.OrgId=org.OrgId

LEFT JOIN (
	Select  COUNT(*) BGC_REMINDERS_SENT, el.emailType, o.OrgId  
	FROM AlphaContact.dbo.EmailLog el
	LEFT JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
	INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
	INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
	INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
	WHERE el.emailType ='BGC_REMINDER' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
	GROUP BY o.OrgId, emailType

) AS BGC_REMINDERS ON BGC_REMINDERS.OrgId=org.OrgId


LEFT JOIN (
	Select  COUNT(*) VERIFICATION_CODES_SENT, el.emailType, o.OrgId  
	FROM AlphaContact.dbo.EmailLog el
	LEFT JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
	INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
	INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
	INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
	WHERE el.emailType ='VERIFICATION_CODE' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
	GROUP BY o.OrgId, emailType

) AS VERIFICATION_CODES ON VERIFICATION_CODES.OrgId=org.OrgId


WHERE prog.leagueId IS NOT NULL 
AND prog.leagueId IN (1,2) 
ORDER BY associations.total_associations_last_day DESC
,reg_submissions.total_reg_submissions_last_day DESC
,training_completions.total_training_completions_last_day DESC
,bgc_submissions.total_bgc_submissions_last_day DESC;

/*
 * 
 * 
 * 
 * 
 * 
 * 


Select  el.*, o.OrgId  
FROM AlphaContact.dbo.EmailLog el
INNER JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
WHERE el.toemail='maneehl@yahoo.com';


Select  COUNT(*), el.emailType, o.OrgId  
FROM AlphaContact.dbo.EmailLog el
INNER JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
WHERE el.emailType ='REG_REMINDER' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
GROUP BY o.OrgId, emailType;

Select  COUNT(*), el.emailType, o.OrgId  
FROM AlphaContact.dbo.EmailLog el
INNER JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
WHERE el.emailType ='BGC_REMINDER' AND  el.dateCreated >= DATEADD(DAY, -1, GETDATE())
GROUP BY o.OrgId, emailType;


SELECT COUNT(*) 
FROM AlphaProgramReg.dbo.Program prog 
JOIN AlphaDesign.dbo.Season s ON s.programId=prog.id AND YEAR(s.DefaultStartDate)=2025 AND MONTH(s.DefaultStartDate) IN (9,10,11)
JOIN AlphaTraining.dbo.SeasonAssignment SA ON SA.SeasonId  =S.SeasonId  
JOIN  AlphaTraining.dbo.CoachClass CC ON SA.SeasonAssignId =CC.SeasonAssignId 
JOIN AlphaProgramReg.dbo.ProgramSubscriptionLOS psl on psl.programId =prog.id AND psl.isActive =1
JOIN AlphaProgramReg.dbo.LevelOfService los on psl.levelOfServiceId =los.id 
JOIN AlphaProgramReg.dbo.League l ON prog.leagueId = l.id 
JOIN AlphaContact.dbo.Organization org ON prog.orgId = org.OrgId 
WHERE CC.CourseId IN (52,53,54,55) AND CC.OverallStatusId LIKE 'C%'  
AND prog.leagueId IS NOT NULL 
AND prog.leagueId IN (1,2) 


Select   DAY(GETDATE()) ,el.*, o.OrgId  
FROM AlphaContact.dbo.EmailLog el
INNER JOIN AlphaContact.dbo.Account a ON a.LoginUserName =el.toEmail 
INNER JOIN AlphaContact.dbo.OrgMember om ON om.AccountId =a.AccountId 
INNER JOIN AlphaContact.dbo.Organization o ON o.OrgId =om.OrgId 
INNER JOIN AlphaContact.dbo.Person p ON p.PersonId =om.PersonId 
WHERE el.emailType ='TRAINING_REMINDER' AND el.dateCreated >= DATEADD(DAY, -1, GETDATE()) 



TRAINING_REMINDER
VERIFICATION_CODE
BGC_REMINDER
REG_REMINDER

*
*
*
**/







