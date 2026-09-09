---------------------------------------------------types-----------------------------------------------------------------------
---------------------------------------------------types-----------------------------------------------------------------------
---------------------------------------------------types-----------------------------------------------------------------------
---------------------------------------------------types-----------------------------------------------------------------------

/*==============================================================
  DateTable
==============================================================*/
IF OBJECT_ID(N'dbo.DateTable', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[DateTable]
    (
        [Date]           [date]          NOT NULL,
        [DayOfWeekName]  [nvarchar](10)  NULL,
        [DayOfWeek]      [tinyint]       NULL,
        CONSTRAINT [PK_DateTable] PRIMARY KEY CLUSTERED ([Date] ASC)
            WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF,
                  ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
            ON [PRIMARY]
    ) ON [PRIMARY];
END
GO

/*==============================================================
  Populate / extend DateTable
==============================================================*/
DECLARE @StartDate date = '2020-01-01';
DECLARE @EndDate   date = '2035-12-31';

;WITH DateRange AS
(
    SELECT @StartDate AS [Date]

    UNION ALL

    SELECT DATEADD(DAY, 1, [Date])
    FROM DateRange
    WHERE [Date] < @EndDate
)
INSERT INTO dbo.DateTable ([Date], [DayOfWeekName], [DayOfWeek])
SELECT
    [Date],
    DATENAME(WEEKDAY, [Date]),
    ((DATEDIFF(DAY, '19000101', [Date]) % 7) + 1)
FROM DateRange
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.DateTable AS D
    WHERE D.[Date] = DateRange.[Date]
)
OPTION (MAXRECURSION 0);
GO

/*==============================================================
  dbo.ChosenParameterType
==============================================================*/
IF TYPE_ID(N'dbo.ChosenParameterType') IS NULL
BEGIN
    CREATE TYPE [dbo].[ChosenParameterType] AS TABLE
    (
        [ParameterId]      [uniqueidentifier] NULL,
        [ResourceGroupId]  [uniqueidentifier] NULL,
        [Value]            [nvarchar](200)    NULL
    );
END
GO

/*==============================================================
  dbo.ManualOrderReservationType
==============================================================*/
IF TYPE_ID(N'dbo.ManualOrderReservationType') IS NULL
BEGIN
    CREATE TYPE [dbo].[ManualOrderReservationType] AS TABLE
    (
        [ReservationId]  [uniqueidentifier] NOT NULL,
        [LocationType]   [int]              NOT NULL,
        [NewOrder]       [int]              NOT NULL
    );
END
GO
---------------------------------------------------functions-----------------------------------------------------------------------
---------------------------------------------------functions-----------------------------------------------------------------------
---------------------------------------------------functions-----------------------------------------------------------------------
---------------------------------------------------functions-----------------------------------------------------------------------
---------------------------------------------------functions-----------------------------------------------------------------------

CREATE OR ALTER FUNCTION [dbo].[SplitToRows] (@column varchar(max), @separator varchar(15))
RETURNS @rtnTable TABLE
  (
  ID int identity(1,1),
  ColumnA varchar(15)
  )
 AS
BEGIN
    DECLARE @position int = 0
    DECLARE @endAt int = 0
    DECLARE @tempString varchar(100)

    set @column = ltrim(rtrim(@column))

    WHILE @position<=len(@column)
    BEGIN       
        set @endAt = CHARINDEX(@separator,@column,@position)
            if(@endAt=0)
            begin
            Insert into @rtnTable(ColumnA) Select substring(@column,@position,len(@column)-@position)
            break;
            end
        set @tempString = substring(ltrim(rtrim(@column)),@position,@endAt-@position)

        Insert into @rtnTable(ColumnA) select @tempString
        set @position=@endAt+1;
    END
    return
END;
GO

/****** Object:  UserDefinedFunction [dbo].[DailyAvailableDatesWithOccurence]    Script Date: 9/8/2026 2:30:34 PM ******/
CREATE OR ALTER FUNCTION [dbo].[DailyAvailableDatesWithOccurence] (
    @startDate DATETIME,
	@endDate DATETIME,
    @servicedays NVARCHAR(100),
    @RecEvery INT,
    @noOfDays INT
)
RETURNS @Result TABLE (
    Date smalldatetime,
    DayName NVARCHAR(10)
)
AS
BEGIN
IF(@endDate IS NOT NULL)
	begin
	 WITH FilteredDates AS (
			SELECT 
				[Date], 
				[DayOfWeekName],
				ROW_NUMBER() OVER (ORDER BY [Date]) AS Number_Of_row
			FROM [dbo].[DateTable] DT
			WHERE
			([Date] BETWEEN @startDate AND @endDate) AND
			DATENAME(weekday, [Date]) IN (SELECT value FROM STRING_SPLIT(@servicedays, ','))
		)

		INSERT INTO @Result
		SELECT
			[Date], 
			[DayOfWeekName]
		FROM FilteredDates
		WHERE (Number_Of_row % @RecEvery) = 1 OR @RecEvery = 1
		OPTION (MAXRECURSION 0);

	end
else
	begin
	 WITH FilteredDates AS (
			SELECT 
				[Date], 
				[DayOfWeekName],
				ROW_NUMBER() OVER (ORDER BY [Date]) AS Number_Of_row
			FROM [dbo].[DateTable] DT
			WHERE DATENAME(weekday, [Date]) IN (SELECT value FROM STRING_SPLIT(@servicedays, ',')) AND
				  [Date] >= @startDate
		)

		INSERT INTO @Result
		SELECT
			TOP(@noOfDays)
			[Date], 
			[DayOfWeekName]
		FROM FilteredDates
		WHERE (Number_Of_row % @RecEvery) = 1 OR @RecEvery = 1
		OPTION (MAXRECURSION 0);

	end
    RETURN;
END;

GO
/****** Object:  UserDefinedFunction [dbo].[MonthlyAvailableDatesWithOccurence]    Script Date: 9/8/2026 2:31:23 PM ******/
CREATE OR ALTER FUNCTION [dbo].[MonthlyAvailableDatesWithOccurence] (
   @startDate DATETIME,
   @endDate DATETIME,
   @serviceDays NVARCHAR(100),
   @RecEvery INT,
   @startServiceDay INT,
   @occurrence INT
)
RETURNS @Result TABLE (Date smalldatetime, DayName NVARCHAR(10))
AS
BEGIN

DECLARE @TempResult TABLE (Date smalldatetime, DayName NVARCHAR(10))
DECLARE @MinRowCount INT

------------------------------------------------------------
--Put days in a table variable to make it easy reach first or last day
------------------------------------------------------------
    DECLARE @SplitDays TABLE (value NVARCHAR(10), RowNum INT);
    INSERT INTO @SplitDays (value, RowNum)
    SELECT value, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
    FROM STRING_SPLIT(@serviceDays, ',');
------------------------------------------------------------------------------------------------------------------
--Insert into @Result table the date and day name with numbered-rows based on @startServiceDay value
--(0 --> first day from @ActiveDays in each month, -1 --> last day, 1 ~ 30 --> this day (ex:day 13 in each month)
------------------------------------------------------------------------------------------------------------------
    IF(@endDate IS NOT NULL)
		BEGIN
			INSERT INTO @TempResult
			SELECT 
				[Date],
				DATENAME(WEEKDAY, [Date]) AS DAYNAME
			FROM (
			SELECT [Date],
			ROW_NUMBER() OVER(PARTITION BY DATEPART(year, [Date]), DATEPART(MONTH, [Date]) ORDER BY [Date]) AS Number_Of_row
			FROM DateTable
			WHERE
			 ([Date] BETWEEN @startDate AND @endDate) AND
			 ((@startServiceDay IS NULL AND DATENAME(WEEKDAY, [Date]) IN (SELECT value FROM @SplitDays)) OR
			 (@startServiceDay > 0  AND @startServiceDay < 32  AND DATEPART(DAY, [Date]) = @startServiceDay and DATENAME(WEEKDAY, [Date]) in (SELECT value FROM @SplitDays)) OR
			 (@startServiceDay = 0  AND [Date] = (SELECT MIN(DATE) FROM DateTable sub WHERE DATEPART(year, sub.[Date]) = DATEPART(year, DateTable.[Date]) AND DATEPART(MONTH, sub.[Date]) = DATEPART(MONTH, DateTable.[Date]) AND DATENAME(WEEKDAY, sub.[Date]) IN (SELECT value FROM @SplitDays))) OR
			 (@startServiceDay = -1 AND [Date] = (SELECT MAX(DATE) FROM DateTable sub WHERE DATEPART(year, sub.[Date]) = DATEPART(year, DateTable.[Date]) AND DATEPART(MONTH, sub.[Date]) = DATEPART(MONTH, DateTable.[Date]) AND DATENAME(WEEKDAY, sub.[Date]) IN (SELECT value FROM @SplitDays))))
    
		)  AS t
			WHERE 
			(DATEDIFF(MONTH, @startDate, [Date]) % @RecEvery = 0)
			OPTION (MAXRECURSION 0); 
		END
		ELSE
		BEGIN
			INSERT INTO @TempResult
			SELECT 
				TOP(@occurrence)
				[Date],
				DATENAME(WEEKDAY, [Date]) AS DAYNAME
			FROM (
			SELECT [Date],
			ROW_NUMBER() OVER(PARTITION BY DATEPART(year, [Date]), DATEPART(MONTH, [Date]) ORDER BY [Date]) AS Number_Of_row
			FROM DateTable
			WHERE
			 ([Date] >= @startDate) AND
			 ((@startServiceDay IS NULL AND DATENAME(WEEKDAY, [Date]) IN (SELECT value FROM @SplitDays)) OR
			 (@startServiceDay > 0  AND @startServiceDay < 32  AND DATEPART(DAY, [Date]) = @startServiceDay and DATENAME(WEEKDAY, [Date]) in (SELECT value FROM @SplitDays)) OR
			 (@startServiceDay = 0  AND [Date] = (SELECT MIN(DATE) FROM DateTable sub WHERE DATEPART(year, sub.[Date]) = DATEPART(year, DateTable.[Date]) AND DATEPART(MONTH, sub.[Date]) = DATEPART(MONTH, DateTable.[Date]) AND DATENAME(WEEKDAY, sub.[Date]) IN (SELECT value FROM @SplitDays))) OR
			 (@startServiceDay = -1 AND [Date] = (SELECT MAX(DATE) FROM DateTable sub WHERE DATEPART(year, sub.[Date]) = DATEPART(year, DateTable.[Date]) AND DATEPART(MONTH, sub.[Date]) = DATEPART(MONTH, DateTable.[Date]) AND DATENAME(WEEKDAY, sub.[Date]) IN (SELECT value FROM @SplitDays))))
    
		)  AS t
			WHERE 
			(DATEDIFF(MONTH, @startDate, [Date]) % @RecEvery = 0)
			OPTION (MAXRECURSION 0); 
		END

		DECLARE @minDateResult DATETIME, @maxDateResult DATETIME, @occurrenceEndDate DATETIME;
		SELECT @minDateResult = MIN(Date),
			   @maxDateResult   = MAX(Date) FROM @TempResult 

			   IF(@occurrence IS NOT NULL)
			   BEGIN
				SELECT @occurrenceEndDate = DATEADD(MONTH, (@occurrence - 1) * @RecEvery, @startDate)
			   END

		IF((DATEPART(MONTH, @startDate) = DATEPART(MONTH, @minDateResult))
				AND (((@startServiceDay IS NULL) OR ((@startServiceDay IS NOT NULL AND @endDate    IS NOT NULL) AND ((SELECT COUNT([Date]) FROM @TempResult) = CEILING(CAST((DATEDIFF(MONTH, @startDate, @endDate) + 1) AS FLOAT) / @RecEvery))))
				OR  ((@startServiceDay  IS NULL) OR ((@startServiceDay IS NOT NULL AND @occurrence IS NOT NULL  AND DATEPART(YEAR, @occurrenceEndDate) = DATEPART(YEAR, @maxDateResult) AND DATEPART(MONTH, @occurrenceEndDate) = DATEPART(MONTH, @maxDateResult)) AND ((SELECT COUNT([Date]) FROM @TempResult) = CEILING(CAST((DATEDIFF(MONTH, @startDate, @occurrenceEndDate) + 1) AS FLOAT) / @RecEvery))))))
		BEGIN
			INSERT INTO @Result
				SELECT * FROM @TempResult
		END

    RETURN;
END;

GO

/****** Object:  UserDefinedFunction [dbo].[ParseChosenParameters]    Script Date: 9/8/2026 2:31:56 PM ******/
CREATE OR ALTER FUNCTION [dbo].[ParseChosenParameters](@ChosenParameters NVARCHAR(MAX))
RETURNS @Result TABLE
(
    ResourceGroupId UNIQUEIDENTIFIER,
    ParameterId UNIQUEIDENTIFIER,
    [Value] NVARCHAR(100)
)
AS
BEGIN
    INSERT INTO @Result
    SELECT ResourceGroupId,
           ParameterId,
           [Value]
    FROM OPENJSON(@ChosenParameters)
         WITH
         (
             ResourceGroupId UNIQUEIDENTIFIER '$.ResourceGroupId',
             ParameterId UNIQUEIDENTIFIER '$.ParameterId',
             [Value] NVARCHAR(100) '$.Value'
         );
    RETURN;
END;

GO

/****** Object:  UserDefinedFunction [dbo].[WeeklyAvailableDatesWithOccurence]    Script Date: 9/8/2026 2:33:24 PM ******/
CREATE OR ALTER FUNCTION [dbo].[WeeklyAvailableDatesWithOccurence] (
   @startDate DATETIME,
   @endDate DATETIME,
   @selectedDays NVARCHAR(100), 
   @RecEvery INT, 
   @occurrence INT
)
RETURNS @Result TABLE ( Date DATETIME, DayName NVARCHAR(10))
AS

Begin

IF(@endDate IS NOT NULL)
	BEGIN
		  INSERT INTO @Result
		  SELECT
		  [Date],
		  DATENAME(WEEKDAY, [Date])
		FROM (
			SELECT [Date], [DayOfWeekName], ROW_NUMBER() OVER(PARTITION BY [DayOfWeekName] ORDER BY [Date]) AS Nuumber_Of_row
			FROM DateTable
			WHERE ([Date] BETWEEN @startDate AND @endDate)
		)  AS T
			WHERE
			DATENAME(WEEKDAY, [Date]) IN (SELECT value from STRING_SPLIT(@selectedDays, ','))

		AND ((Nuumber_Of_row % @RecEvery) = 1 or @RecEvery = 1)
		OPTION (MAXRECURSION 0);
	END
	ELSE
		BEGIN
			INSERT INTO @Result
				  SELECT TOP(@occurrence * (SELECT COUNT(value) FROM STRING_SPLIT(@selectedDays, ',')))
				  [Date],
				  DATENAME(WEEKDAY, [Date])
				FROM (
					SELECT [Date], [DayOfWeekName], ROW_NUMBER() OVER(PARTITION BY [DayOfWeekName] ORDER BY [Date]) AS Nuumber_Of_row
					FROM DateTable
					WHERE ([Date] BETWEEN @startDate AND DATEADD(WEEK, (@occurrence * @RecEvery), @startDate))
				)  AS T
					WHERE
					DATENAME(WEEKDAY, [Date]) IN (SELECT value FROM STRING_SPLIT(@selectedDays, ','))
					
					AND ((Nuumber_Of_row % @RecEvery) = 1 or @RecEvery = 1)
                    ORDER BY Nuumber_Of_row
					OPTION (MAXRECURSION 0);			
		 END
 RETURN
END;

GO

/****** Object:  UserDefinedFunction [dbo].[IsServiceTimeSlotAndRegionValid]    Script Date: 9/8/2026 2:36:28 PM ******/
CREATE OR ALTER FUNCTION [dbo].[IsServiceTimeSlotAndRegionValid]
(
    @ServiceId UNIQUEIDENTIFIER,
    @TimeSlotId UNIQUEIDENTIFIER,
    @RegionId UNIQUEIDENTIFIER, -- Customer Region
    @FromTime TIME = NULL,
    @ToTime   TIME = NULL
)
RETURNS BIT
AS
BEGIN
    DECLARE @IsLimitedToRegion BIT;

    SELECT @IsLimitedToRegion = new_islimitedtoregion
    FROM new_rvservice
    WHERE new_rvserviceId = @ServiceId;

    -- Service must support the requested time slot
    IF NOT EXISTS
    (
        SELECT 1
        FROM new_servicetimeslot
        WHERE new_service = @ServiceId
          AND new_timeslot = @TimeSlotId
    )
    OR
    (
        @IsLimitedToRegion = 1
        AND NOT EXISTS
        (
            SELECT 1
            FROM new_serviceregionsaddresses sra
            INNER JOIN new_regionservice rs
                ON rs.new_region = sra.new_serviceregion
               AND rs.new_service = @ServiceId
            INNER JOIN region serviceRegion
                ON serviceRegion.regionId = sra.new_serviceregion
            LEFT JOIN new_regiontimeslot rts
                ON rts.new_region = serviceRegion.regionId
            LEFT JOIN new_timeslot ts
                ON ts.new_timeslotId = rts.new_timeslot
            WHERE sra.new_customerlocation = @RegionId
              AND
              (
                    serviceRegion.new_islimited IS NULL
                 OR serviceRegion.new_islimited <> 1
                 OR
                 (
                        @FromTime IS NOT NULL
                    AND @ToTime IS NOT NULL
                    AND CAST(ts.new_startingtime AS TIME) <= @FromTime
                    AND CAST(ts.new_endingtime AS TIME) >= @ToTime
                 )
              )
        )
    )
    BEGIN
        RETURN 0;
    END;

    RETURN 1;
END;

GO
---------------------------------------------------stored procedures-----------------------------------------------------------------------
---------------------------------------------------stored procedures-----------------------------------------------------------------------
---------------------------------------------------stored procedures-----------------------------------------------------------------------
---------------------------------------------------stored procedures-----------------------------------------------------------------------





/****** Object:  StoredProcedure [dbo].[GetTimeSlotsByServiceId]    Script Date: 9/8/2026 1:42:46 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetTimeSlotsByServiceId]     
@ServiceId UNIQUEIDENTIFIER     
AS     
BEGIN     
    SET NOCOUNT ON;     
     
  
    if not EXISTS( select 1 from new_rvservice where new_rvservice.new_rvserviceId = @ServiceId)  
        THROW 50001 , 'service not found' , 1;  
  
    SELECT      
        new_timeslot.new_timeslotId AS [KEY],     
        new_timeslot.new_name AS [ValueEn], 
        new_timeslot.new_displaynamear AS [ValueAr],     
        new_timeslot.new_shift AS Shift,     
        new_timeslot.new_hours AS Hours ,    
        new_timeslot.new_weekdaysoptions as EnableDays,  
        new_timeslot.new_serviceoffset as ServiceOffset   ,  
        new_timeslot.new_startingtime as StartTime   
    FROM new_servicetimeslot     
    INNER JOIN new_timeslot      
        ON new_servicetimeslot.new_timeslot = new_timeslot.new_timeslotId     
    WHERE      
        new_timeslot.new_type = 1     
        AND new_servicetimeslot.new_service = @ServiceId  
        AND new_timeslot.statecode = '1000'  
        And new_servicetimeslot.statecode = '1000'  
    ORDER BY new_timeslot.new_startingtime  
END ;

GO

/****** Object:  StoredProcedure [dbo].[GetServiceLinePricingReportV01]    Script Date: 9/8/2026 1:45:30 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetServiceLinePricingReportV01]
(
    @ServiceId         UNIQUEIDENTIFIER,
    @PriceListId       UNIQUEIDENTIFIER = NULL,
    @BillingOption     INT = NULL,
    @RegionId          UNIQUEIDENTIFIER = NULL,
    @ChosenParameters  dbo.ChosenParameterType READONLY,
    @WeeksCsv          NVARCHAR(200) = N'1,2,3,4',
    @PerWeekCsv        NVARCHAR(200) = N'1,2,3,4,5,6,7'
)
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------------------------------
    -- Temp tables
    --------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Factors') IS NOT NULL DROP TABLE #Factors;
    IF OBJECT_ID('tempdb..#TS') IS NOT NULL DROP TABLE #TS;
    IF OBJECT_ID('tempdb..#Regions') IS NOT NULL DROP TABLE #Regions;
    IF OBJECT_ID('tempdb..#Conditions') IS NOT NULL DROP TABLE #Conditions;
    IF OBJECT_ID('tempdb..#Weeks') IS NOT NULL DROP TABLE #Weeks;
    IF OBJECT_ID('tempdb..#PerWeek') IS NOT NULL DROP TABLE #PerWeek;
    IF OBJECT_ID('tempdb..#TSRegion') IS NOT NULL DROP TABLE #TSRegion;
    IF OBJECT_ID('tempdb..#Scenarios') IS NOT NULL DROP TABLE #Scenarios;
    IF OBJECT_ID('tempdb..#MatchedFactors') IS NOT NULL DROP TABLE #MatchedFactors;
    IF OBJECT_ID('tempdb..#FactorContrib') IS NOT NULL DROP TABLE #FactorContrib;
    IF OBJECT_ID('tempdb..#ScenarioResult') IS NOT NULL DROP TABLE #ScenarioResult;

    --------------------------------------------------------------------------------
    -- 1. Resolve pricelist  (same precedence as GetOrderServiceLinePriceFactors)
    --------------------------------------------------------------------------------
    DECLARE @ResolvedPriceListId UNIQUEIDENTIFIER;

    IF @PriceListId IS NOT NULL
        SET @ResolvedPriceListId = @PriceListId;
    ELSE
        SELECT TOP 1 @ResolvedPriceListId = sp.new_pricelist
        FROM new_servicepricelist sp
            INNER JOIN new_pricelist pl ON sp.new_pricelist = pl.new_pricelistid
        WHERE sp.new_service = @ServiceId
              AND sp.new_isdefault = 1
              AND (@BillingOption IS NULL OR pl.new_paymenttype = @BillingOption);

    --------------------------------------------------------------------------------
    -- 2. Template + base unit price
    --------------------------------------------------------------------------------
    DECLARE @PriceFactorTemplateId UNIQUEIDENTIFIER;
    DECLARE @BaseUnitPrice DECIMAL(18,4);

    SELECT @PriceFactorTemplateId = pl.new_pricefactortemplate,
           @BaseUnitPrice = CAST(pl.new_unitprice AS DECIMAL(18,4))
    FROM new_pricelist pl
    WHERE pl.new_pricelistid = @ResolvedPriceListId;

    --------------------------------------------------------------------------------
    -- 3. Factors for this template (materialized for reuse)
    --------------------------------------------------------------------------------
    SELECT pf.new_pricefactorId          AS Id,
           pf.new_name                   AS Name,
           pf.new_nameen                 AS NameEn,
           pf.new_name_appleview         AS Name_appleview,
           pf.new_nameen_appleview       AS NameEn_appleview,
           pf.new_adjustmenttype         AS AdjustmentType,
           CAST(pf.new_adjustmentvalue AS DECIMAL(18,4)) AS AdjustmentValue,
           pf.new_factortype             AS FactorType,
           pf.new_overwriteunitprice     AS OverwriteUnitPrice,
           pf.new_factorconditions       AS FactorConditions
    INTO #Factors
    FROM new_pricefactor pf
    WHERE pf.new_pricefactortemplate = @PriceFactorTemplateId;

    --------------------------------------------------------------------------------
    -- 4. Axis: timeslots offered for the service  (hours from the timeslot)
    --------------------------------------------------------------------------------
    SELECT DISTINCT
           t.new_timeslotId   AS TimeslotId,
           t.new_name         AS TimeslotName,
           t.new_hours        AS Hours,
           t.new_startingtime AS FromTime,
           t.new_endingtime   AS ToTime
    INTO #TS
    FROM new_servicetimeslot st
        INNER JOIN new_timeslot t ON st.new_timeslot = t.new_timeslotId
    WHERE st.new_service = @ServiceId;

    --------------------------------------------------------------------------------
    -- 5. Axis: regions referenced in factor conditions (+ optional @RegionId)
    --------------------------------------------------------------------------------
    CREATE TABLE #Regions (RegionId UNIQUEIDENTIFIER);

    INSERT INTO #Regions (RegionId)
    SELECT DISTINCT TRY_CAST(JSON_VALUE(crit.value, '$.value') AS UNIQUEIDENTIFIER)
    FROM #Factors pf
        CROSS APPLY OPENJSON(pf.FactorConditions, '$.rules')
            WITH (criteria NVARCHAR(MAX) AS JSON) rules
        CROSS APPLY OPENJSON(rules.criteria) crit
    WHERE pf.FactorConditions IS NOT NULL
          AND JSON_VALUE(crit.value, '$.field') = 'region'
          AND JSON_VALUE(crit.value, '$.operator') = '='
          AND TRY_CAST(JSON_VALUE(crit.value, '$.value') AS UNIQUEIDENTIFIER) IS NOT NULL;

    IF @RegionId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM #Regions WHERE RegionId = @RegionId)
        INSERT INTO #Regions (RegionId) VALUES (@RegionId);

    DECLARE @HasRegionAxis BIT = IIF(EXISTS (SELECT 1 FROM #Regions), 1, 0);

    --------------------------------------------------------------------------------
    -- 6. Valid (timeslot, region) pairs
    --------------------------------------------------------------------------------
    CREATE TABLE #TSRegion
    (
        TimeslotId UNIQUEIDENTIFIER,
        Hours INT,
        RegionId UNIQUEIDENTIFIER NULL
    );

    IF @HasRegionAxis = 1
    BEGIN
        INSERT INTO #TSRegion (TimeslotId, Hours, RegionId)
        SELECT t.TimeslotId, t.Hours, r.RegionId
        FROM #TS t
            CROSS JOIN #Regions r
        WHERE dbo.IsServiceTimeSlotAndRegionValid(@ServiceId, t.TimeslotId, r.RegionId, t.FromTime, t.ToTime) = 1;
    END
    ELSE
    BEGIN
        -- region is not price-relevant for this service: keep all service timeslots
        INSERT INTO #TSRegion (TimeslotId, Hours, RegionId)
        SELECT t.TimeslotId, t.Hours, NULL
        FROM #TS t;
    END

    --------------------------------------------------------------------------------
    -- 7. Axis: condition (baseline + EVERY parameter_condition that belongs to the
    --     service's mandatory condition groups, new_type = 1000 -- not just the ones
    --     referenced in a factor's rules). Conditions no factor touches still appear;
    --     they simply match no factor rule and fall through to the base rate, so the
    --     matching logic is unchanged -- the report just shows the full set.
    --
    --     Chain: new_servicecondationgroup (new_service = @ServiceId, new_type = 1000)
    --            -> new_condationgroup ==> new_indv_parameter_condtion_group
    --            <== new_parameter_condition_group  new_indv_parameter_condtion
    --------------------------------------------------------------------------------
    CREATE TABLE #Conditions (ConditionId UNIQUEIDENTIFIER NULL);

    INSERT INTO #Conditions (ConditionId) VALUES (NULL);    -- baseline: no condition

    INSERT INTO #Conditions (ConditionId)
    SELECT DISTINCT PC.new_indv_parameter_condtionId
    FROM new_servicecondationgroup SCG
        INNER JOIN new_indv_parameter_condtion_group CG
            ON SCG.new_condationgroup = CG.new_indv_parameter_condtion_groupId
        INNER JOIN new_indv_parameter_condtion PC
            ON PC.new_parameter_condition_group = CG.new_indv_parameter_condtion_groupId
    WHERE SCG.new_service = @ServiceId
          AND SCG.new_type = 1000;

    --------------------------------------------------------------------------------
    -- 8. Axes: weeks and per-week
    --------------------------------------------------------------------------------
    SELECT TRY_CAST(LTRIM(RTRIM(value)) AS INT) AS Weeks
    INTO #Weeks
    FROM STRING_SPLIT(@WeeksCsv, ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    SELECT TRY_CAST(LTRIM(RTRIM(value)) AS INT) AS PerWeek
    INTO #PerWeek
    FROM STRING_SPLIT(@PerWeekCsv, ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    --------------------------------------------------------------------------------
    -- 9. Scenario grid
    --------------------------------------------------------------------------------
    CREATE TABLE #Scenarios
    (
        ScenarioId        INT IDENTITY(1,1) PRIMARY KEY,
        TimeslotId        UNIQUEIDENTIFIER,
        Hours             INT,
        RegionId          UNIQUEIDENTIFIER NULL,
        Weeks             INT,
        PerWeek           INT,
        TotalReservations INT,
        ConditionId       UNIQUEIDENTIFIER NULL
    );

    INSERT INTO #Scenarios (TimeslotId, Hours, RegionId, Weeks, PerWeek, TotalReservations, ConditionId)
    SELECT tr.TimeslotId,
           tr.Hours,
           tr.RegionId,
           w.Weeks,
           pw.PerWeek,
           w.Weeks * pw.PerWeek,
           c.ConditionId
    FROM #TSRegion tr
        CROSS JOIN #Weeks w
        CROSS JOIN #PerWeek pw
        CROSS JOIN #Conditions c;

    --------------------------------------------------------------------------------
    -- 10. Match factors per scenario.
    --     The matcher predicate is ported verbatim, but evaluated in stages so the
    --     scenario columns are LOCAL to the aggregate (a SUM/CASE that mixes inner
    --     JSON columns with outer scenario columns is illegal -- error 8124 -- which
    --     is why this is staged rather than a single correlated subquery).
    --
    --       a. #FactorCrit   : one row per (factor, rule-logic, criterion)
    --       b. #CritEval      : per (scenario, factor, rule-logic, criterion) match flag,
    --                           plus the criterion field/operator/value (for the WHY trace)
    --       c. RuleEval/fail  : aggregate flags to rule level, find failing rules
    --       d. #MatchedFactors: unconditioned factors + conditioned factors with no failing rule
    --------------------------------------------------------------------------------

    -- a. explode factor conditions into criterion rows (conditioned factors only)
    IF OBJECT_ID('tempdb..#FactorCrit') IS NOT NULL DROP TABLE #FactorCrit;
    SELECT f.Id            AS FactorId,
           rules.logic     AS Logic,
           crit.value      AS Crit
    INTO #FactorCrit
    FROM #Factors f
        CROSS APPLY OPENJSON(f.FactorConditions, '$.rules')
            WITH (logic NVARCHAR(10) '$.logic', criteria NVARCHAR(MAX) AS JSON) rules
        CROSS APPLY OPENJSON(rules.criteria) crit
    WHERE f.FactorConditions IS NOT NULL
          AND LTRIM(RTRIM(f.FactorConditions)) <> ''
          AND f.FactorConditions <> '[]';

    -- b. evaluate each criterion against each scenario (row-level: mixing columns is fine here).
    --    We also carry the raw criterion parts so the WHY trace can render/resolve them later.
    IF OBJECT_ID('tempdb..#CritEval') IS NOT NULL DROP TABLE #CritEval;
    SELECT s.ScenarioId,
           c.FactorId,
           c.Logic,
           JSON_VALUE(c.Crit, '$.field')       AS Field,
           JSON_VALUE(c.Crit, '$.operator')    AS Operator,
           JSON_VALUE(c.Crit, '$.value')       AS RawValue,
           JSON_VALUE(c.Crit, '$.parameterId') AS ParamId,
           JSON_VALUE(c.Crit, '$.min')         AS MinVal,
           JSON_VALUE(c.Crit, '$.max')         AS MaxVal,
           CAST(CASE
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'timeslot'
                         AND JSON_VALUE(c.Crit, '$.operator') = '='
                         AND JSON_VALUE(c.Crit, '$.value') = s.TimeslotId THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'region'
                         AND JSON_VALUE(c.Crit, '$.operator') = '='
                         AND JSON_VALUE(c.Crit, '$.value') = s.RegionId THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'region'
                         AND JSON_VALUE(c.Crit, '$.operator') = '!='
                         AND s.RegionId IS NOT NULL
                         AND JSON_VALUE(c.Crit, '$.value') <> s.RegionId THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'visit_count'
                         AND JSON_VALUE(c.Crit, '$.operator') = '='
                         AND TRY_CAST(JSON_VALUE(c.Crit, '$.value') AS INT) = s.TotalReservations THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'visit_count'
                         AND JSON_VALUE(c.Crit, '$.operator') = '!='
                         AND TRY_CAST(JSON_VALUE(c.Crit, '$.value') AS INT) <> s.TotalReservations THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'visit_count'
                         AND JSON_VALUE(c.Crit, '$.operator') = '>'
                         AND s.TotalReservations > TRY_CAST(JSON_VALUE(c.Crit, '$.value') AS INT) THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'visit_count'
                         AND JSON_VALUE(c.Crit, '$.operator') = '<'
                         AND s.TotalReservations < TRY_CAST(JSON_VALUE(c.Crit, '$.value') AS INT) THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'visit_count'
                         AND JSON_VALUE(c.Crit, '$.operator') = 'BETWEEN'
                         AND s.TotalReservations
                             BETWEEN TRY_CAST(JSON_VALUE(c.Crit, '$.min') AS INT)
                                 AND TRY_CAST(JSON_VALUE(c.Crit, '$.max') AS INT) THEN 1
                    WHEN JSON_VALUE(c.Crit, '$.field') = 'parameter'
                         AND cpMatch.MatchFlag = 1 THEN 1
                    WHEN pcm.ParamCondMatch = 1 THEN 1
                    ELSE 0
                END AS INT) AS IsMatch
    INTO #CritEval
    FROM #FactorCrit c
        CROSS JOIN #Scenarios s
        OUTER APPLY
        (
            SELECT TOP 1 1 AS MatchFlag
            FROM @ChosenParameters cp
            WHERE JSON_VALUE(c.Crit, '$.field') = 'parameter'
                  AND cp.ParameterId = JSON_VALUE(c.Crit, '$.parameterId')
                  AND cp.Value = JSON_VALUE(c.Crit, '$.value')
        ) cpMatch
        OUTER APPLY
        (
            SELECT CASE
                       WHEN JSON_VALUE(c.Crit, '$.field') = 'parameter_condition'
                            AND JSON_VALUE(c.Crit, '$.operator') = '='
                            AND s.ConditionId IS NOT NULL
                            AND JSON_VALUE(c.Crit, '$.value') = s.ConditionId THEN 1
                       ELSE 0
                   END AS ParamCondMatch
        ) pcm;

    -- c + d. roll up to rule level, then to matched (scenario, factor) pairs
    ;WITH RuleEval AS
    (
        SELECT ScenarioId,
               FactorId,
               Logic,
               COUNT(*)      AS TotalCriteria,
               SUM(IsMatch)  AS MatchedCriteria      -- plain column: no outer reference
        FROM #CritEval
        GROUP BY ScenarioId, FactorId, Logic
    ),
    FailingScenarioFactor AS
    (
        SELECT DISTINCT ScenarioId, FactorId
        FROM RuleEval
        WHERE (Logic = 'AND' AND MatchedCriteria <> TotalCriteria)
              OR (Logic = 'OR' AND MatchedCriteria = 0)
    ),
    UnconditionedFactors AS
    (
        SELECT f.Id AS FactorId
        FROM #Factors f
        WHERE f.FactorConditions IS NULL
              OR LTRIM(RTRIM(f.FactorConditions)) = ''
              OR f.FactorConditions = '[]'
              OR NOT EXISTS (SELECT 1 FROM OPENJSON(f.FactorConditions, '$.rules'))
    ),
    ConditionedFactors AS
    (
        SELECT DISTINCT FactorId FROM #FactorCrit
    ),
    MatchedPairs AS
    (
        -- unconditioned factors apply to every scenario
        SELECT s.ScenarioId, u.FactorId
        FROM #Scenarios s
            CROSS JOIN UnconditionedFactors u
        UNION
        -- conditioned factors apply where no rule fails
        SELECT s.ScenarioId, cf.FactorId
        FROM #Scenarios s
            CROSS JOIN ConditionedFactors cf
        WHERE NOT EXISTS
        (
            SELECT 1 FROM FailingScenarioFactor x
            WHERE x.ScenarioId = s.ScenarioId AND x.FactorId = cf.FactorId
        )
    )
    SELECT mp.ScenarioId,
           f.Id              AS FactorId,
           f.Name,
           f.NameEn,
           f.AdjustmentType,
           f.AdjustmentValue,
           f.OverwriteUnitPrice
    INTO #MatchedFactors
    FROM MatchedPairs mp
        INNER JOIN #Factors f ON f.Id = mp.FactorId;

    --------------------------------------------------------------------------------
    -- 11. Resolve unit price per scenario (highest matched overwrite wins) + base
    --------------------------------------------------------------------------------
    ;WITH OverwriteByScenario AS
    (
        SELECT ScenarioId, MAX(AdjustmentValue) AS OverwriteValue
        FROM #MatchedFactors
        WHERE OverwriteUnitPrice = 1
        GROUP BY ScenarioId
    )
    SELECT s.ScenarioId,
           s.TimeslotId,
           s.Hours,
           s.RegionId,
           s.Weeks,
           s.PerWeek,
           s.TotalReservations,
           s.ConditionId,
           CAST(COALESCE(o.OverwriteValue, @BaseUnitPrice) AS DECIMAL(18,4)) AS UnitPrice,
           CAST(s.TotalReservations * s.Hours * COALESCE(o.OverwriteValue, @BaseUnitPrice) AS DECIMAL(18,4)) AS Base
    INTO #ScenarioResult
    FROM #Scenarios s
        LEFT JOIN OverwriteByScenario o ON o.ScenarioId = s.ScenarioId;

    --------------------------------------------------------------------------------
    -- 12. Per-factor contribution
    --------------------------------------------------------------------------------
    SELECT mf.ScenarioId,
           mf.FactorId,
           mf.Name,
           mf.NameEn,
           mf.AdjustmentType,
           mf.AdjustmentValue,
           mf.OverwriteUnitPrice,
           CAST(CASE
                    WHEN mf.OverwriteUnitPrice = 1 THEN N'Overwrite'
                    WHEN mf.AdjustmentType = 1 THEN N'Fixed'
                    WHEN mf.AdjustmentType = 2 THEN N'Percentage'
                    ELSE N'Skipped'
                END AS NVARCHAR(20)) AS Role,
           CAST(CASE
                    WHEN mf.OverwriteUnitPrice = 1 THEN 0          -- defines unit price, not a surcharge
                    WHEN mf.AdjustmentType = 1 THEN r.TotalReservations * r.Hours * mf.AdjustmentValue
                    WHEN mf.AdjustmentType = 2 THEN r.Base * mf.AdjustmentValue / 100.0
                    ELSE 0                                          -- other types skipped
                END AS DECIMAL(18,4)) AS Contribution
    INTO #FactorContrib
    FROM #MatchedFactors mf
        INNER JOIN #ScenarioResult r ON r.ScenarioId = mf.ScenarioId;

    --------------------------------------------------------------------------------
    -- RESULT SET [1]  -- scenario summary
    --------------------------------------------------------------------------------
    SELECT r.ScenarioId,
           r.TimeslotId,
           ts.TimeslotName,
           r.Hours,
           r.RegionId,
           r.Weeks,
           r.PerWeek,
           r.TotalReservations,
           r.ConditionId,
           COALESCE(cond.new_name, N'بدون شرط / None') AS ConditionName,
           r.UnitPrice,
           @BaseUnitPrice AS BaseUnitPrice,
           r.Base,
           CAST(r.Base + ISNULL(fc.TotalContribution, 0) AS DECIMAL(18,4)) AS FinalPrice
    FROM #ScenarioResult r
        LEFT JOIN #TS ts ON ts.TimeslotId = r.TimeslotId
        INNER JOIN new_indv_parameter_condtion cond ON cond.new_indv_parameter_condtionId = r.ConditionId
        OUTER APPLY
        (
            SELECT SUM(c.Contribution) AS TotalContribution
            FROM #FactorContrib c
            WHERE c.ScenarioId = r.ScenarioId
        ) fc
    ORDER BY r.TimeslotId, r.RegionId, r.ConditionId, r.Weeks, r.PerWeek;

    --------------------------------------------------------------------------------
    -- RESULT SET [2]  -- per-scenario factor detail, WITH a bilingual WHY trace.
    --   MatchReasonAr/En list every criterion that fired for the factor on that
    --   scenario (all criteria of an AND rule, or the matched ones of an OR rule),
    --   with timeslot / parameter_condition / parameter values resolved to names.
    --   Factors that carry no conditions show an "always applies" note.
    --------------------------------------------------------------------------------
    ;WITH MatchedReason AS
    (
        SELECT ce.ScenarioId,
               ce.FactorId,
               ReasonAr =
                   CASE ce.Field
                       WHEN 'timeslot' THEN N'الفترة الزمنية = ' + ISNULL(ts.new_name, ce.RawValue)
                       WHEN 'region' THEN CASE WHEN ce.Operator = '!=' THEN N'المنطقة ضمن المسموح بها'
                                               ELSE N'المنطقة مطابقة للمطلوبة' END
                       WHEN 'visit_count' THEN N'عدد الزيارات '
                             + CASE ce.Operator
                                   WHEN '=' THEN N'= ' + ISNULL(ce.RawValue, N'')
                                   WHEN '!=' THEN N'≠ ' + ISNULL(ce.RawValue, N'')
                                   WHEN '>' THEN N'> ' + ISNULL(ce.RawValue, N'')
                                   WHEN '<' THEN N'< ' + ISNULL(ce.RawValue, N'')
                                   WHEN 'BETWEEN' THEN N'بين ' + ISNULL(ce.MinVal, N'') + N' و ' + ISNULL(ce.MaxVal, N'')
                                   ELSE ISNULL(ce.Operator, N'') + N' ' + ISNULL(ce.RawValue, N'')
                               END
                       WHEN 'parameter' THEN ISNULL(prm.new_name, N'معيار') + N' = ' + ISNULL(ce.RawValue, N'')
                       WHEN 'parameter_condition' THEN N'الشرط: ' + ISNULL(pc.new_name, ce.RawValue)
                       ELSE ce.Field
                   END,
               ReasonEn =
                   CASE ce.Field
                       WHEN 'timeslot' THEN 'timeslot = ' + ISNULL(ts.new_name, ce.RawValue)
                       WHEN 'region' THEN CASE WHEN ce.Operator = '!=' THEN 'region within allowed'
                                               ELSE 'region = selected region' END
                       WHEN 'visit_count' THEN 'visit count '
                             + CASE ce.Operator
                                   WHEN '=' THEN '= ' + ISNULL(ce.RawValue, '')
                                   WHEN '!=' THEN '<> ' + ISNULL(ce.RawValue, '')
                                   WHEN '>' THEN '> ' + ISNULL(ce.RawValue, '')
                                   WHEN '<' THEN '< ' + ISNULL(ce.RawValue, '')
                                   WHEN 'BETWEEN' THEN 'between ' + ISNULL(ce.MinVal, '') + ' and ' + ISNULL(ce.MaxVal, '')
                                   ELSE ISNULL(ce.Operator, '') + ' ' + ISNULL(ce.RawValue, '')
                               END
                       WHEN 'parameter' THEN ISNULL(prm.new_name, 'parameter') + ' = ' + ISNULL(ce.RawValue, '')
                       WHEN 'parameter_condition' THEN 'condition: ' + ISNULL(pc.new_name, ce.RawValue)
                       ELSE ce.Field
                   END
        FROM #CritEval ce
            LEFT JOIN new_timeslot ts
                ON ce.Field = 'timeslot'
                AND TRY_CAST(ce.RawValue AS UNIQUEIDENTIFIER) = ts.new_timeslotId
            LEFT JOIN new_indv_parameter_condtion pc
                ON ce.Field = 'parameter_condition'
                AND TRY_CAST(ce.RawValue AS UNIQUEIDENTIFIER) = pc.new_indv_parameter_condtionId
            LEFT JOIN new_rvparameter prm
                ON ce.Field = 'parameter'
                AND TRY_CAST(ce.ParamId AS UNIQUEIDENTIFIER) = prm.new_rvparameterId
        WHERE ce.IsMatch = 1
    ),
    ReasonAgg AS
    (
        SELECT ScenarioId,
               FactorId,
               STRING_AGG(ReasonAr, N' + ') AS MatchReasonAr,
               STRING_AGG(ReasonEn, ' + ')  AS MatchReasonEn
        FROM MatchedReason
        GROUP BY ScenarioId, FactorId
    )
    SELECT fc.ScenarioId,
           fc.FactorId,
           fc.Name,
           fc.NameEn,
           fc.AdjustmentType,
           fc.AdjustmentValue,
           fc.OverwriteUnitPrice,
           @BaseUnitPrice AS BaseUnitPrice,
           fc.Role,
           fc.Contribution,
           COALESCE(ra.MatchReasonAr, N'بدون شروط (ينطبق دائماً)') AS MatchReasonAr,
           COALESCE(ra.MatchReasonEn, 'No conditions (always applies)') AS MatchReasonEn
    FROM #FactorContrib fc
        LEFT JOIN ReasonAgg ra
            ON ra.ScenarioId = fc.ScenarioId AND ra.FactorId = fc.FactorId
    ORDER BY fc.ScenarioId, fc.Role, fc.Name;

END;

GO
/****** Object:  StoredProcedure [dbo].[GetSelectedCountriesByService]    Script Date: 9/8/2026 1:48:21 PM ******/
CREATE OR ALTER  PROCEDURE [dbo].[GetSelectedCountriesByService]  
    @ServiceId UNIQUEIDENTIFIER  
AS  
BEGIN  
    SET NOCOUNT ON;  
  
    WITH IDS AS (  
        SELECT IDS.[value]  
        FROM new_servicechosenparameter AS chosenParams  
        CROSS APPLY STRING_SPLIT(chosenParams.new_value, ',') AS IDS  
        WHERE chosenParams.new_service = @ServiceId
        and chosenParams.statuscode = 1000  
        and chosenParams.statecode = 1
    )  
    SELECT   
        new_country.new_countryId AS [Key],  
        new_country.new_name AS [Value] , 
        new_country.new_imageurl [Image] 
    FROM new_country  
    INNER JOIN IDS  
        ON new_country.new_countryId = IDS.[value]  
END;

GO
/****** Object:  StoredProcedure [dbo].[GetOrderServiceLinePromotionPriceFactors]    Script Date: 9/8/2026 1:49:53 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetOrderServiceLinePromotionPriceFactors]
(
    @ServiceId UNIQUEIDENTIFIER,
    @TimeslotId UNIQUEIDENTIFIER = NULL,
    @RegionId UNIQUEIDENTIFIER = NULL,
    @PriceListId UNIQUEIDENTIFIER = NULL,
    @NumberOfReservations INT = NULL,
    @BillingOption INT = NULL,
    @ChosenParameters dbo.ChosenParameterType READONLY
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ResolvedPriceListId UNIQUEIDENTIFIER;

    -- 1. Resolve pricelist (same as before)
    IF @PriceListId IS NOT NULL
        SET @ResolvedPriceListId = @PriceListId;
    ELSE
        SELECT TOP 1
               @ResolvedPriceListId = sp.new_pricelist
        FROM new_servicepricelist sp
            INNER JOIN new_pricelist pl
                ON sp.new_pricelist = pl.new_pricelistid
        WHERE sp.new_service = @ServiceId
              AND sp.new_isdefault = 1
              AND
              (
                  @BillingOption IS NULL
                  OR pl.new_paymenttype = @BillingOption
              );

    ;WITH CandidateFactors AS
    (
        SELECT promo.new_hourlypromotionid as PromotionId,
               promo.new_name AS PromotionName,
               plp.new_priority,
               pf.new_pricefactorId,
               pf.new_name,
               pf.new_adjustmenttype,
               pf.new_adjustmentvalue,
               pf.new_factortype,
               pf.new_factorvalueone,
               pf.new_factorvaluetwo,
               pf.new_overwriteunitprice AS OverwriteUnitPrice
        FROM new_pricelistpromotion plp
             INNER JOIN new_hourlypromotion promo
                 ON plp.new_promotion = promo.new_hourlypromotionid
             INNER JOIN new_pricefactortemplate tmpl
                 ON promo.new_template = tmpl.new_pricefactortemplateid
             INNER JOIN new_pricefactor pf
                 ON pf.new_pricefactortemplate = tmpl.new_pricefactortemplateid
        WHERE plp.new_pricelist = @ResolvedPriceListId
              AND EXISTS
        (
            SELECT 1
            FROM OPENJSON(pf.new_factorconditions, '$.rules') AS rules
                CROSS APPLY OPENJSON(rules.value, '$.criteria') AS crit
                OUTER APPLY
            (
                SELECT TOP 1
                       1 AS MatchFlag
                FROM @ChosenParameters cp
                WHERE JSON_VALUE(crit.value, '$.field') = 'parameter'
                      AND cp.ParameterId = JSON_VALUE(crit.value, '$.parameterId')
                      AND cp.Value = JSON_VALUE(crit.value, '$.value')
            ) AS cpMatch
            GROUP BY rules.[key],
                     rules.value
            HAVING COUNT(*) = SUM(   CASE
                                         -- Timeslot
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'timeslot'
                                              AND JSON_VALUE(crit.value, '$.operator') = '='
                                              AND JSON_VALUE(crit.value, '$.value') = @TimeslotId THEN 1
                                         -- Region
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'region'
                                              AND JSON_VALUE(crit.value, '$.operator') = '='
                                              AND JSON_VALUE(crit.value, '$.value') = @RegionId THEN 1
                                         -- Visit Count =
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'visit_count'
                                              AND JSON_VALUE(crit.value, '$.operator') = '='
                                              AND TRY_CAST(JSON_VALUE(crit.value, '$.value') AS INT) = @NumberOfReservations THEN 1
                                         -- Visit Count >
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'visit_count'
                                              AND JSON_VALUE(crit.value, '$.operator') = '>'
                                              AND @NumberOfReservations > TRY_CAST(JSON_VALUE(crit.value, '$.value') AS INT) THEN 1
                                         -- Visit Count <
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'visit_count'
                                              AND JSON_VALUE(crit.value, '$.operator') = '<'
                                              AND @NumberOfReservations < TRY_CAST(JSON_VALUE(crit.value, '$.value') AS INT) THEN 1
                                         -- Visit Count BETWEEN
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'visit_count'
                                              AND JSON_VALUE(crit.value, '$.operator') = 'BETWEEN'
                                              AND @NumberOfReservations
                                                  BETWEEN TRY_CAST(JSON_VALUE(crit.value, '$.min') AS INT) 
                                                          AND TRY_CAST(JSON_VALUE(crit.value, '$.max') AS INT) THEN 1
                                         -- ChosenParameter
                                         WHEN JSON_VALUE(crit.value, '$.field') = 'parameter'
                                              AND cpMatch.MatchFlag = 1 THEN 1
                                         ELSE 0
                                     END
                                 )
        )
    ),
    RankedPromotions AS
    (
        SELECT cf.*,
               RANK() OVER (ORDER BY cf.new_priority DESC) AS PromoRank
        FROM CandidateFactors cf
    )
    SELECT new_pricefactorId,
           new_name,
           new_adjustmenttype,
           new_adjustmentvalue,
           new_factortype,
           OverwriteUnitPrice,
           PromotionName,
           new_priority, 
           PromotionId
    FROM RankedPromotions
    WHERE PromoRank = 1; -- only factors of the highest-priority promotion (per pricelistpromotion)
END;

    

/****** Object:  StoredProcedure [dbo].[GetHourlyAvailableResourcesV11]    Script Date: 9/8/2026 1:55:17 PM ******/
    -- V12 vs V11 parity fixes (see also GetHourlyAvailableDaysV12):
--   * Adds anonymous @ContactId special case to the blocklist check so
--     anonymous callers are not filtered by every customer's blocklist.
--   * Adds new_laboroffset to the reservation-overlap check so the same
--     reservation is treated as overlapping here as in the Days SP.
--   * Excludes service vacation dates from #TempCalendarDates so this SP
--     no longer returns rows for dates Days SP already excluded (which
--     would silently mis-index reservation<->resource pairing in the C#
--     workflow, since it pairs availableDays[i] with availableResources[i]).
--   * Fixes the ChosenParameters insert to write both target columns
--     (ResourceId + ResourceGroupId).

GO
CREATE OR ALTER PROCEDURE [dbo].[GetHourlyAvailableResourcesV11]
(
    @TimeSlotId UNIQUEIDENTIFIER,
    @ReccurrenceOptionId UNIQUEIDENTIFIER,
    @ServiceId UNIQUEIDENTIFIER,
    @RegionId UNIQUEIDENTIFIER,
    @ContactId UNIQUEIDENTIFIER,
    @ServiceProvider UNIQUEIDENTIFIER,
    @StartDate DATETIME,
    @EndDate DATETIME = NULL,
    @Occurrence INT = NULL,
    @Count INT,
    @SelectedDays NVARCHAR(80) = NULL,
    @ChosenParameters NVARCHAR(MAX) = NULL,
    @ParamterCondationIds NVARCHAR(MAX) = NuLL
)
AS
BEGIN
    DECLARE @ServiceDays NVARCHAR(80);
    DECLARE @FromTime TIME;
    DECLARE @ToTime TIME;
    DECLARE @Hours INT;
    DECLARE @MinDate DATETIME;
    DECLARE @MaxDate DATETIME;
    DECLARE @RecEvery INT;
    DECLARE @DayNum INT;
    DECLARE @RecurrenceType INT;

    SELECT @RecEvery = RecOption.new_recevery,
           @DayNum = RecOption.new_daynumber,
           @RecurrenceType = RecOption.new_type
    FROM new_recurrenceoption RecOption
    WHERE new_recurrenceoptionId = @ReccurrenceOptionId

    IF OBJECT_ID('tempdb..#TempCalendarDates') IS NOT NULL
        DROP TABLE #TempCalendarDates;

    IF OBJECT_ID('tempdb..#TempFinalResult') IS NOT NULL
        DROP TABLE #TempFinalResult;

    IF OBJECT_ID('tempdb..#TempServiceResourceGroupAvailability') IS NOT NULL
        DROP TABLE #TempServiceResourceGroupAvailability;

    IF OBJECT_ID('tempdb..#ResourcesWithChosenParameters') IS NOT NULL
        DROP TABLE #ResourcesWithChosenParameters;

    CREATE TABLE #TempCalendarDates
    (
        [Date] DATETIME,
        [DayName] NVARCHAR(50),
        [FromTime] DATETIME2,
        [ToTime] DATETIME2
    );

    IF OBJECT_ID('tempdb..#ChosenParametersTable') IS NOT NULL
        DROP TABLE #ChosenParametersTable;

    IF OBJECT_ID('tempdb..#TempServiceDays') IS NOT NULL
        DROP TABLE #TempServiceDays;


    CREATE TABLE #TempServiceDays
    (
        [DayName] NVARCHAR(20)
    );

    CREATE TABLE #ChosenParametersTable
    (
        ResourceGroupId UNIQUEIDENTIFIER,
        ParameterId UNIQUEIDENTIFIER,
        Value NVARCHAR(100)
    );

    CREATE TABLE #ResourcesWithChosenParameters
    (
        ResourceId UNIQUEIDENTIFIER,
        ResourceGroupId UNIQUEIDENTIFIER
    );

    SELECT @FromTime = timeslot.new_startingtime,
           @ToTime = timeslot.new_endingtime,
           @Hours = timeslot.new_hours,
           @ServiceDays = timeslot.new_weekdays
    FROM new_timeslot timeslot
    WHERE new_timeslotId = @timeSlotId


    IF dbo.IsServiceTimeSlotAndRegionValid(@ServiceId, @TimeSlotId, @RegionId, @FromTime, @ToTime) = 0
    BEGIN
        PRINT ('InValid TimeSlot Or Region')
         RETURN;
    END ;

    IF @ChosenParameters IS NOT NULL
    BEGIN

        INSERT INTO #ChosenParametersTable
        SELECT *
        FROM dbo.ParseChosenParameters(@ChosenParameters);


        -- parity: was inserting one column into a two-column table; write both.
        INSERT INTO #ResourcesWithChosenParameters (ResourceId, ResourceGroupId)
        SELECT resource.new_rvresourceId AS ResourceId,
               resource.new_rvresourcegroup AS ResourceGroupId
        FROM new_rvresource [resource]
            INNER JOIN new_rvresourceparameter resourceparameter
                ON resourceparameter.new_rvresource = resource.new_rvresourceId
            INNER JOIN #ChosenParametersTable
                ON resource.new_rvresourcegroup = #ChosenParametersTable.ResourceGroupId
                   AND resourceparameter.new_rvparameter = #ChosenParametersTable.ParameterId
                   AND  resourceparameter.new_value = #ChosenParametersTable.[Value]
                   AND resourceparameter.new_rvresource = resource.new_rvresourceId

        if (select count(*) from #ResourcesWithChosenParameters) < @count
            return null;


    END
    ELSE If  @ParamterCondationIds is not null
    begin

        WITH CondationParamterIds AS (
                SELECT CAST([value] AS UNIQUEIDENTIFIER) AS Id
                FROM STRING_SPLIT(@ParamterCondationIds, ',')
            )

            INSERT Into #ResourcesWithChosenParameters (ResourceId, ResourceGroupId)
            select RP.new_rvresource as ResourceId,
                   r.new_rvresourcegroup as ResourceGroupId
            from new_servicecondationgroup SCG
            Inner Join new_indv_parameter_condtion_group CG
            on SCG.new_condationgroup = CG.new_indv_parameter_condtion_groupId

            INNER join new_indv_parameter_condtion PC
            on CG.new_indv_parameter_condtion_groupId = PC.new_parameter_condition_group

            Inner Join new_rvresourceparameter RP
            on PC.new_parameter = RP.new_rvparameter

            Inner Join new_rvresource  R
            on RP.new_rvresource = R.new_rvresourceId

                            LEFT JOIN
                    new_indv_baseparameter_condtion BPC
                    ON BPC.new_indv_baseparameter_condtionId = PC.new_baseparameter_condtion
                CROSS APPLY
                    STRING_SPLIT(ISNULL(BPC.new_value, PC.new_value), ',') ss

            where SCG.new_type = 1000

            and SCG.new_service = @ServiceId

            and RP.new_value = ss.[value]

            and PC.new_indv_parameter_condtionId IN (
                select * from CondationParamterIds
            )

            if (select count(*) from #ResourcesWithChosenParameters) < @count
                    return;

    END
    ELSE
    begin
        return null
    End

    INSERT INTO #TempServiceDays
    SELECT columnA
    FROM dbo.SplitToRows(@ServiceDays + ',', ',');

    WITH CalDays
    AS (SELECT [DATE],
               [DayName]
        FROM
        (
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[DailyAvailableDatesWithOccurence](@StartDate, @EndDate, @ServiceDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 0
            UNION ALL
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[WeeklyAvailableDatesWithOccurence](@StartDate, @EndDate, @SelectedDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 1
            UNION ALL
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[MonthlyAvailableDatesWithOccurence](
                                                               @StartDate,
                                                               @EndDate,
                                                               @ServiceDays,
                                                               @RecEvery,
                                                               @DayNum,
                                                               @Occurrence
                                                           )
            WHERE @RecurrenceType = 2
        ) AS Combined )

    INSERT INTO #TempCalendarDates
    SELECT [DATE],
           [DayName],
           CAST(
                DATEADD(HOUR,
                    DATEDIFF(HOUR, 0, CalDays.[Date]),
                    CAST(@FromTime AS DATETIME2)
                    )
                AS DATETIME2
                ) AS FromTime,
           DATEADD(
                      DAY,
                      IIF(@ToTime < @FromTime, 1, 0),
                      CAST(
                        DATEADD(
                            HOUR,
                            DATEDIFF(HOUR, 0, CalDays.[Date]),
                            CAST(@ToTime AS DATETIME2)
                            )
                            AS DATETIME2
                        )
                  ) AS ToTime
    FROM CalDays;

    -- parity: drop service vacation dates so this SP does not return
    -- resources for days already excluded by GetHourlyAvailableDaysV12.
    DELETE FROM #TempCalendarDates
    WHERE CAST([Date] AS DATE) IN
    (
        SELECT CAST([official-vacation].new_date AS DATE)
        FROM new_rvservice AS service
        INNER JOIN new_servicevacany AS [service-vacation]
            ON service.new_rvserviceId = [service-vacation].new_service
        INNER JOIN new_officialvacancy AS [official-vacation]
            ON [official-vacation].new_officialvacancyId = [service-vacation].new_officialvacancy
        WHERE service.new_rvserviceId = @ServiceId
    );

    SELECT @MinDate = MIN([Date]),
           @MaxDate = MAX([Date])
    FROM #TempCalendarDates;

    WITH ServiceResourceGroups
    AS (SELECT serviceresource.new_rvresourcegroup AS rvresourcegroupId,
               serviceresource.new_quantity * @Count AS RequiredQuantity
        FROM new_rvserviceresource serviceresource
        WHERE serviceresource.new_rvservice = @ServiceId),
    RelationDefinitions
    AS (SELECT new_rvrelationdefinition.new_rvresourcegroup,
               new_rvrelationtype.new_schemaname,
               new_rvparameter.new_rvparameterId,
               new_rvresourcegroup.new_name RSGroupName
        FROM new_rvrelationdefinition
            INNER JOIN new_rvrelationtype
                ON new_rvrelationdefinition.new_rvrelationtype = new_rvrelationtype.new_rvrelationtypeId
            INNER JOIN new_rvresourcegroup
                ON new_rvresourcegroup.new_rvresourcegroupId = new_rvrelationdefinition.new_rvresourcegroup
            LEFT OUTER JOIN new_rvparameter
                ON new_rvparameter.new_type = 2
                   AND new_rvparameter.new_rvresourcegroup = new_rvrelationdefinition.new_rvresourcegroup
                   AND new_rvparameter.new_typeschemaname = new_rvrelationtype.new_schemaname
        WHERE new_rvrelationdefinition.new_rvservice = @ServiceId)
        ,
    ParameterConditions AS (
        SELECT
            conditionGrp.new_name conditionGrpName,
            ParameterCondition.new_name paramConditionName,
            ParameterCondition.new_parameter parameterId,
            operator.new_value operator,
            ParameterCondition.new_value [Value]
            FROM
            new_indv_parameter_condtion_group conditionGrp
            INNER JOIN new_indv_parameter_condtion ParameterCondition
            ON conditionGrp.new_indv_parameter_condtion_groupId = ParameterCondition.new_parameter_condition_group
            INNER Join new_servicecondationgroup as scg
            ON conditionGrp.new_indv_parameter_condtion_groupId = scg.new_condationgroup
            AND scg.new_service = @ServiceId
            INNER JOIN new_parameteroperator operator
            ON operator.new_parameteroperatorId = ParameterCondition.new_operator
            where  scg.new_type = 1001
    )
    ,
    Resources AS (
        SELECT
            r.new_name,
            r.new_rvresourceId,
            r.new_rvresourcegroup,
            rg.new_name AS RSGroupName,
            r.new_capacity,
            rd.new_schemaname AS RelationType,
            rp.new_value AS RelationValue,
            cal.new_availabilitystartdate AS CalenderStartDate,
            cal.new_availabilityenddate AS CalenderEndDate,
            cal.new_maxworkinghoursperday AS MaxWorkingHours,
            cal.new_weekdays AS CalenderTimeSlotsDays
        FROM new_rvresource r
            INNER JOIN new_rvresourcegroup rg
                ON rg.new_rvresourcegroupId = r.new_rvresourcegroup
            INNER JOIN ServiceResourceGroups srg
                ON r.new_rvresourcegroup = srg.rvresourcegroupId
            LEFT JOIN RelationDefinitions rd
                ON r.new_rvresourcegroup = rd.new_rvresourcegroup
            LEFT JOIN new_rvresourceparameter rp
                ON rp.new_rvresource = r.new_rvresourceId
                AND rp.new_rvparameter = rd.new_rvparameterId
            LEFT JOIN new_regionresource rr
                ON rr.new_resource = r.new_rvresourceId
            OUTER APPLY (
                SELECT
                    cal.new_availabilitystartdate,
                    cal.new_availabilityenddate,
                    cal.new_maxworkinghoursperday,
                    ts.new_weekdays
                FROM new_rvresourcecalendar cal
                    LEFT JOIN new_resourcecalendartimeslot rcts
                        ON cal.new_islimitedtotimeslot = 1
                        AND cal.new_rvresourcecalendarId = rcts.new_resourcecalendar
                    LEFT JOIN new_timeslot ts
                        ON rcts.new_timeslot = ts.new_timeslotId
                WHERE
                    -- parity: skip the blocklist check for anonymous contact
                    -- so anonymous callers are not filtered by every customer's block.
                    (
                        @ContactId IS NULL
                        OR @ContactId = '00000000-0000-0000-0000-000000000000'
                        OR NOT EXISTS (
                            SELECT 1
                            FROM new_contactblockresource bl
                            WHERE bl.new_resource = r.new_rvresourceId
                                    AND bl.new_customer = @ContactId
                        )
                    )
                AND cal.new_rvresource = r.new_rvresourceId
                                    AND
                    (
                        cal.new_islimitedtotimeslot = 0

                        OR

                        (
                            cal.new_islimitedtotimeslot = 1
                            AND ts.new_timeslotId IS NOT NULL
                            AND CAST(ts.new_startingtime AS TIME) <= CAST(@FromTime AS TIME)
                            AND CAST(ts.new_endingtime AS TIME) >= CAST(@ToTime AS TIME)
                        )
                    )
            ) cal
        WHERE
            (r.new_serviceprovider = @ServiceProvider)
            AND   (
                    (
                        @ChosenParameters IS NULL
                        OR NOT EXISTS
                        (
                            SELECT 1
                            FROM #ChosenParametersTable CPT
                            WHERE CPT.ResourceGroupId = r.new_rvresourcegroup
                        )
                        OR r.new_rvresourceId IN
                        (
                            SELECT R.ResourceId FROM #ResourcesWithChosenParameters R
                        )
                    )
                    AND
                    (
                        Not Exists (
                            SELECT 1
                            FROM #ResourcesWithChosenParameters
                            where #ResourcesWithChosenParameters.ResourceGroupId = r.new_rvresourcegroup
                        )
                        OR
                        (
                            (
                                Not Exists(select 1 from #ResourcesWithChosenParameters)
                                OR
                                Exists (
                                    select 1 from #ResourcesWithChosenParameters
                                    where r.new_rvresourceId = #ResourcesWithChosenParameters.ResourceId
                                )
                            )
                            AND
                            (
                                Not Exists(select 1 from ParameterConditions)
                                OR
                                EXISTS (
                                    SELECT 1
                                    FROM ParameterConditions pc
                                    INNER JOIN new_rvresourceparameter rp2
                                        ON rp2.new_rvparameter = pc.parameterId
                                        AND rp2.new_rvresource = r.new_rvresourceId
                                    WHERE
                                        (
                                            (pc.operator = '=' AND rp2.new_value = pc.[Value])
                                            OR
                                            (pc.operator = '<>' AND rp2.new_value <> pc.[Value])
                                            OR
                                            (
                                                pc.operator = 'IN'
                                                AND EXISTS (
                                                    SELECT 1
                                                    FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                )
                                            )
                                            OR
                                            (
                                                pc.operator = 'NOT IN'
                                                AND NOT EXISTS (
                                                    SELECT 1
                                                    FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                )
                                            )
                                        )
                                )
                            )
                        )
                    )
                  )

            AND
            (
                r.new_islimitedtoregion IS NULL
                OR r.new_islimitedtoregion != 1
                OR rr.new_region = @RegionId
            )

    )
    ,
        ResourcesWithDates
    AS (SELECT Resources.*,
               RequestedDates.*
        FROM Resources
            CROSS JOIN #TempServiceDays AS ServiceDays
            INNER JOIN #TempCalendarDates RequestedDates
                ON RequestedDates.DayName = ServiceDays.DayName
        WHERE Resources.CalenderStartDate <= RequestedDates.DATE
              AND Resources.CalenderEndDate >= RequestedDates.DATE
              AND
              (
                  Resources.CalenderTimeSlotsDays IS NULL
                  OR CHARINDEX(ServiceDays.[DayName], Resources.CalenderTimeSlotsDays) > 0
              ))
              ,
         AvailableResourcesWithDates
    AS (SELECT DISTINCT
               ResourcesWithDates.DATE,
               ResourcesWithDates.DayName,
               ResourcesWithDates.new_name,
               ResourcesWithDates.new_rvresourcegroup,
               ResourcesWithDates.RSGroupName,
               ResourcesWithDates.new_rvresourceId,
               ResourcesWithDates.RelationType,
               ResourcesWithDates.RelationValue,
               ISNULL(workedHours, 0) workedHours,
               new_capacity - ISNULL(reservedQuantity, 0) AvailableQuantity,
               ResourcesWithDates.ToTime,
               ResourcesWithDates.FromTime,
               resourcestoppeddays.new_startstoppingdate,
               resourcestoppeddays.new_endstoppingdate
        FROM ResourcesWithDates
            LEFT JOIN new_resourcestoppeddays resourcestoppeddays
                ON ResourcesWithDates.new_rvresourceId = resourcestoppeddays.new_resource
            OUTER APPLY
        (
            SELECT ResourcesWithDates.new_rvresourceId,
                   SUM(reservationresource.new_quantity) AS reservedQuantity,
                   SUM(new_timeslot.new_hours) AS workedHours
            FROM new_reservation reservation
                INNER JOIN new_reservationresource reservationresource
                    ON reservation.new_reservationId = reservationresource.new_reservation
                INNER JOIN new_timeslot
                    ON new_timeslot.new_timeslotId = reservation.new_timeslot
            WHERE ResourcesWithDates.new_rvresourceId = reservationresource.new_rvresource
                  AND ResourcesWithDates.DATE = CAST(ResourcesWithDates.FromTime AS DATE)
                  AND
                  (
                      -- parity: apply new_laboroffset on both sides of the
                      -- reservation window, matching Days SP overlap semantics.
                      (
                          DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime)
                              >= ResourcesWithDates.FromTime
                          AND DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime)
                              <= ResourcesWithDates.ToTime
                      )
                      OR
                      (
                          DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime)
                              >= ResourcesWithDates.FromTime
                          AND DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime)
                              <= ResourcesWithDates.ToTime
                      )
                      OR
                      (
                          DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime)
                              <= ResourcesWithDates.FromTime
                          AND DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime)
                              >= ResourcesWithDates.ToTime
                      )
                  )
        ) AS resourceReservations
        WHERE ISNULL(workedHours, 0) + @Hours <= MaxWorkingHours
              AND new_capacity > ISNULL(reservedQuantity, 0)
              AND
              (
                  (
                      resourcestoppeddays.new_startstoppingdate IS NULL
              AND resourcestoppeddays.new_endstoppingdate IS NULL
                  )
                  OR (resourcestoppeddays.new_endstoppingdate < ResourcesWithDates.FromTime)
                  OR (resourcestoppeddays.new_startstoppingdate > ResourcesWithDates.ToTime)
              )

              ),
    ResourceRelations
    AS (SELECT DISTINCT
               RelationType,
               RelationValue
        FROM Resources

        ),
         RelationDefinitionsCrossData
    AS (SELECT RelationDefinitions.new_rvresourcegroup RSGroup,
               RelationType,
               RelationValue,
               RSGroupName
        FROM RelationDefinitions
            INNER JOIN ResourceRelations
                ON ResourceRelations.RelationType = RelationDefinitions.new_schemaname),
         AvaliableResourcesWithRelations
    AS (SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
               ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
               ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
               ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
               ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
               Resources.DATE,
               Resources.new_rvresourceId
        FROM AvailableResourcesWithDates Resources
            FULL OUTER JOIN RelationDefinitionsCrossData
                ON (
                       RelationDefinitionsCrossData.RelationType = Resources.RelationType
                       OR
                       (
                           Resources.RelationType IS NULL
                           AND RelationDefinitionsCrossData.RelationType IS NULL
                       )
                   )
                   AND
                   (
                       RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                       OR
                       (
                           Resources.RelationValue IS NULL
                           AND RelationDefinitionsCrossData.RelationValue IS NULL
                       )
                   )
                   AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
        WHERE AvailableQuantity IS NOT NULL
        UNION ALL
        SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
               ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
               ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
               ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
               ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
               DistinctDates.DATE,
               Resources.new_rvresourceId
        FROM AvailableResourcesWithDates Resources
            FULL OUTER JOIN RelationDefinitionsCrossData
                ON (
                       RelationDefinitionsCrossData.RelationType = Resources.RelationType
                       OR
                       (
                           Resources.RelationType IS NULL
                           AND RelationDefinitionsCrossData.RelationType IS NULL
                       )
                   )
                   AND
                   (
                       RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                       OR
                       (
                           Resources.RelationValue IS NULL
                           AND RelationDefinitionsCrossData.RelationValue IS NULL
                       )
                   )
                   AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
            CROSS JOIN #TempCalendarDates DistinctDates
        WHERE AvailableQuantity IS NULL),
         AvaliableResourcesGroupedByResGroupAndRelation
    AS (SELECT new_rvresourcegroup,
               RelationType,
               RelationValue,
               RSGroupName,
               DATE,
               SUM(AvailableQuantity) AS AvailableQuantity
        FROM AvaliableResourcesWithRelations
        GROUP BY DATE,
                 new_rvresourcegroup,
                 RelationType,
                 RelationValue,
                 RSGroupName),
         MinQuantityForByRelation
    AS (SELECT RelationType,
               RelationValue,
               DATE,
               MIN(ISNULL(AvailableQuantity, 0)) AS MinQuantityForRSGroup
        FROM AvaliableResourcesGroupedByResGroupAndRelation
        WHERE RelationType IS NOT NULL
        GROUP BY DATE,
                 RelationType,
                 RelationValue),
         MinAvaliableQuantityByResourceGroupAndRelation
    AS (SELECT AvailableRes.DATE,
               AvailableRes.new_rvresourcegroup,
               AvailableRes.RelationType,
               AvailableRes.RelationValue,
               AvailableRes.RSGroupName,
               MinQuantityForRSGroup,
               AvailableQuantity av,
               ISNULL(MinQuantityForRSGroup, AvailableQuantity) AS MinAvailableQuantity
        FROM AvaliableResourcesGroupedByResGroupAndRelation AvailableRes
            LEFT OUTER JOIN MinQuantityForByRelation
                ON MinQuantityForByRelation.RelationType = AvailableRes.RelationType
                   AND
                   (
                       MinQuantityForByRelation.RelationValue = AvailableRes.RelationValue
                       OR
                       (
                           MinQuantityForByRelation.RelationValue IS NULL
                           AND AvailableRes.RelationValue IS NULL
                       )
                   )
                   AND
                   (
                       MinQuantityForByRelation.DATE = AvailableRes.DATE
                       OR MinQuantityForByRelation.DATE IS NULL
                   )),
         MinAvailableResourceGroup
    AS (SELECT DATE,
               new_rvresourcegroup,
               RSGroupName,
               SUM(MinAvailableQuantity) AS AvailableQuantity
        FROM MinAvaliableQuantityByResourceGroupAndRelation
        WHERE DATE IS NOT NULL
        GROUP BY DATE,
                 new_rvresourcegroup,
                 RSGroupName),
         ServiceResourceGroupAvailability
    AS (SELECT DATENAME(WEEKDAY, [Date]) AS DayName,
               DATE,
               MinAvailableResourceGroup.new_rvresourcegroup,
               RSGroupName,
               MinAvailableResourceGroup.AvailableQuantity,
               ServiceResourceGroups.RequiredQuantity,
               IIF(MinAvailableResourceGroup.AvailableQuantity >= ServiceResourceGroups.RequiredQuantity, 1, 0) AS IsAvailable
        FROM MinAvailableResourceGroup
            INNER JOIN ServiceResourceGroups
                ON ServiceResourceGroups.rvresourcegroupId = MinAvailableResourceGroup.new_rvresourcegroup),
         ResourcesByRelation
    AS (SELECT ARR.DATE,
               ARR.RSGroupName,
               ARR.new_rvresourcegroup AS RSGroup,
               ARR.RelationType,
               ARR.RelationValue,
               ARR.new_rvresourceId,
               ARR.AvailableQuantity,
               SRG.RequiredQuantity,
               ROW_NUMBER() OVER (PARTITION BY ARR.DATE,
                                               ARR.new_rvresourcegroup,
                                               ARR.RelationValue
                                  ORDER BY ARR.AvailableQuantity DESC
   ) AS ResourceRank
        FROM AvaliableResourcesWithRelations ARR
            INNER JOIN ServiceResourceGroupAvailability SRGA
                ON ARR.new_rvresourcegroup = SRGA.new_rvresourcegroup
                   AND ARR.DATE = SRGA.DATE
                   AND SRGA.IsAvailable = 1
            INNER JOIN ServiceResourceGroups SRG
                ON ARR.new_rvresourcegroup = SRG.rvresourcegroupId
        WHERE ARR.AvailableQuantity > 0),

         RelationResourceAvailability
    AS (SELECT DATE,
               RelationType,
               RelationValue,
               COUNT(DISTINCT RSGroup) AS AvailableResourceGroups,
               (
                   SELECT COUNT(DISTINCT rvresourcegroupId)FROM ServiceResourceGroups
               ) AS RequiredResourceGroups,
               CASE
                   WHEN COUNT(DISTINCT RSGroup) =
                   (
                       SELECT COUNT(DISTINCT rvresourcegroupId)FROM ServiceResourceGroups
                   ) THEN
                       1
                   ELSE
                       0
               END AS CanFulfillService
        FROM ResourcesByRelation
        WHERE RelationType IS NOT NULL
        GROUP BY DATE,
                 RelationType,
                 RelationValue),

         ValidRelations
    AS (SELECT DATE,
               RelationType,
               RelationValue,
               ROW_NUMBER() OVER (PARTITION BY DATE ORDER BY RelationValue) AS RelationPriority
        FROM RelationResourceAvailability
        WHERE CanFulfillService = 1

        ),

         ResourceAllocations
    AS (SELECT RBR.DATE,
               RBR.RSGroup,
               RBR.new_rvresourceId,
               RBR.RequiredQuantity,
               RBR.RelationValue,
               RBR.RSGroupName,
               RBR.AvailableQuantity,
               VR.RelationPriority,
               CASE
                   WHEN RBR.RequiredQuantity > 1 THEN
                       RBR.ResourceRank
                   ELSE
                       1
               END AS ResourceInstance
        FROM ResourcesByRelation RBR
            INNER JOIN ValidRelations VR
                ON RBR.DATE = VR.DATE
                   AND RBR.RelationType = VR.RelationType
                   AND RBR.RelationValue = VR.RelationValue
        WHERE
            (
                RBR.RequiredQuantity = 1
                AND RBR.ResourceRank = 1
            )
            OR
            (
                RBR.RequiredQuantity > 1
                AND RBR.ResourceRank <= RBR.RequiredQuantity
            )
         ),

         FinalResourceAssignments
    AS (SELECT RA.DATE,
               RA.RSGroup,
               RA.new_rvresourceId,
               RA.RequiredQuantity,
               RA.RelationValue AS RelationValue,
               RA.AvailableQuantity,
               Numbers.VisitNumber
        FROM ResourceAllocations RA
            CROSS JOIN
            (
                SELECT TOP (
                           (
                               SELECT MAX(RequiredQuantity)FROM ServiceResourceGroups
                           )
                           )
                       ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VisitNumber
            ) Numbers
        WHERE
            (
                RA.RequiredQuantity > 1
                AND Numbers.VisitNumber <= RA.RequiredQuantity
            )
            OR
            (
                RA.RequiredQuantity = 1
                AND Numbers.VisitNumber <=
                (
                    SELECT MAX(RequiredQuantity)FROM ServiceResourceGroups
                )
            )

            AND RA.RelationPriority = 1)

    SELECT DISTINCT
           FRA.DATE,
           FRA.RSGroup AS [RSGroupId],
           FRA.new_rvresourceId AS [ResourceId],
           FRA.RequiredQuantity,
           FRA.AvailableQuantity,
           FRA.RelationValue,
           FRA.VisitNumber
    FROM FinalResourceAssignments FRA
    ORDER BY FRA.DATE,
             FRA.RelationValue,
             FRA.RSGroup,
             FRA.VisitNumber;
END;

GO
/****** Object:  StoredProcedure [dbo].[GetHourlyAvailableDaysV11]    Script Date: 9/8/2026 1:56:39 PM ******/
-- V12 vs V11 parity fixes (see also GetHourlyAvailableResourcesV12):
--   * Adds new_resourcestoppeddays filter to AvailableResourcesWithDates so
--     stopped resources are not counted as available (Resources SP already
--     filtered them out; without this, Days SP could return a date that
--     Resources SP later returns zero rows for, silently shifting the
--     reservation<->resource index pairing in the C# workflow).
CREATE OR ALTER PROCEDURE [dbo].[GetHourlyAvailableDaysV11]
(
    @TimeSlotId UNIQUEIDENTIFIER,
    @ReccurrenceOptionId UNIQUEIDENTIFIER,
    @ServiceId UNIQUEIDENTIFIER,
    @RegionId UNIQUEIDENTIFIER,
    @ContactId UNIQUEIDENTIFIER = NULL,
    @ServiceProvider UNIQUEIDENTIFIER,
    @StartDate DATETIME,
    @EndDate DATETIME = NULL,
    @Occurrence INT = NULL,
    @Count INT,
    @SelectedDays NVARCHAR(80) = NULL,
    @ChosenParameters NVARCHAR(MAX) = NULL,
    @ParamterCondationIds NVARCHAR(MAX) = NULL
)
AS
BEGIN
    DECLARE @ServiceDays NVARCHAR(80);
    DECLARE @FromTime TIME;
    DECLARE @ToTime TIME;
    DECLARE @Hours INT;
    DECLARE @MinDate DATETIME;
    DECLARE @MaxDate DATETIME;
    DECLARE @RecEvery INT;
    DECLARE @DayNum INT;
    DECLARE @RecurrenceType INT;
    DECLARE @ServiceResGrpCount INT;
    DECLARE @ParameterizedResGrpCount INT;
    DECLARE @AvailableParameterizedResGrpCount INT;

    IF OBJECT_ID('tempdb..#TempCalendarDates') IS NOT NULL
        DROP TABLE #TempCalendarDates;
    IF OBJECT_ID('tempdb..#TempServiceDays') IS NOT NULL
        DROP TABLE #TempServiceDays;
    IF OBJECT_ID('tempdb..#TempServiceResourceGroups') IS NOT NULL
        DROP TABLE #TempServiceResourceGroups;
    IF OBJECT_ID('tempdb..#ChosenParametersTable') IS NOT NULL
        DROP TABLE #ChosenParametersTable;
    IF OBJECT_ID('tempdb..#ResourcesWithChosenParameters') IS NOT NULL
        DROP TABLE #ResourcesWithChosenParameters;
    IF OBJECT_ID('tempdb..#TempServiceResourceGroupAvailability') IS NOT NULL
        DROP TABLE #TempServiceResourceGroupAvailability;

    CREATE TABLE #TempCalendarDates
    (
        [Date] DATETIME,
        [DayName] NVARCHAR(50),
        [FromTime] DATETIME2,
        [ToTime] DATETIME2
    );

    CREATE TABLE #TempServiceDays
    (
        [DayName] NVARCHAR(20)
    );

    CREATE TABLE #TempServiceResourceGroups
    (
        rvresourcegroupId UNIQUEIDENTIFIER,
        RequiredQuantity INT
    );

    CREATE TABLE #ChosenParametersTable
    (
        ResourceGroupId UNIQUEIDENTIFIER,
        ParameterId UNIQUEIDENTIFIER,
        Value NVARCHAR(100)
    );

    CREATE TABLE #ResourcesWithChosenParameters
    (
        ResourceId UNIQUEIDENTIFIER,
        ResourceGroupId UNIQUEIDENTIFIER
    );


    SELECT @FromTime = timeslot.new_startingtime,
           @ToTime = timeslot.new_endingtime,
           @Hours = timeslot.new_hours,
           @ServiceDays = timeslot.new_weekdays
    FROM new_timeslot timeslot
    WHERE new_timeslotId = @timeSlotId


    SELECT @RecEvery = RecOption.new_recevery,
           @DayNum = RecOption.new_daynumber,
           @RecurrenceType = RecOption.new_type
    FROM new_recurrenceoption RecOption
    WHERE new_recurrenceoptionId = @ReccurrenceOptionId;

    DECLARE @RegionWeekDays NVARCHAR(80);

    SELECT TOP 1
        @RegionWeekDays = timeslot.new_weekdays
    FROM region
    INNER JOIN new_regiontimeslot rt
        ON region.regionId = rt.new_region
    INNER JOIN new_timeslot timeslot
        ON rt.new_timeslot = timeslot.new_timeslotId
    WHERE region.regionId = @RegionId
      AND region.new_islimited = 1;


    IF dbo.IsServiceTimeSlotAndRegionValid(@ServiceId, @TimeSlotId, @RegionId, @FromTime, @ToTime) = 0
    BEGIN
        print('Invalid Region or Timeslot')
        RETURN;
    END;


    WITH ServiceResourceGroups
    AS (SELECT serviceresource.new_rvresourcegroup AS rvresourcegroupId,
               serviceresource.new_quantity * @Count AS RequiredQuantity
        FROM new_rvserviceresource serviceresource
        WHERE serviceresource.new_rvservice = @ServiceId)
    INSERT INTO #TempServiceResourceGroups
    (
        rvresourcegroupId,
        RequiredQuantity
    )
    SELECT rvresourcegroupId,
           RequiredQuantity
    FROM ServiceResourceGroups;

    SELECT @ServiceResGrpCount = COUNT(rvresourcegroupId)
    FROM #TempServiceResourceGroups


    IF @ChosenParameters IS NOT NULL
        BEGIN

            INSERT INTO #ChosenParametersTable
            SELECT *
            FROM dbo.ParseChosenParameters(@ChosenParameters);


            WITH ChosenParametersCount
            AS (SELECT ResourceGroupId,
                    COUNT(*) AS ParameterCount
                FROM #ChosenParametersTable
                GROUP BY ResourceGroupId)



            INSERT INTO #ResourcesWithChosenParameters
            SELECT resource.new_rvresourceId,
                resource.new_rvresourcegroup
            FROM new_rvresource [resource]
                INNER JOIN new_rvresourceparameter resourceparameter
                    ON resourceparameter.new_rvresource = resource.new_rvresourceId
                INNER JOIN #ChosenParametersTable
                    ON resource.new_rvresourcegroup = #ChosenParametersTable.ResourceGroupId
                    AND resourceparameter.new_rvparameter = #ChosenParametersTable.ParameterId
                    AND resourceparameter.new_value = #ChosenParametersTable.[Value]
                INNER JOIN ChosenParametersCount chosenCount
                    ON #ChosenParametersTable.ResourceGroupId = chosenCount.ResourceGroupId
            GROUP BY resource.new_rvresourceId,
                    resource.new_rvresourcegroup
            HAVING COUNT(new_rvresourceId) = MAX(chosenCount.ParameterCount)


            SELECT @AvailableParameterizedResGrpCount = COUNT(DISTINCT ResourceGroupId)
            FROM #ResourcesWithChosenParameters Rwc
            WHERE Rwc.ResourceGroupId IN
            (
                SELECT DISTINCT ResourceGroupId FROM #ChosenParametersTable
            )


            SELECT @ParameterizedResGrpCount = COUNT(DISTINCT ResourceGroupId)
            FROM #ChosenParametersTable

            IF (@ParameterizedResGrpCount != @AvailableParameterizedResGrpCount)
            BEGIN
                PRINT (@ParameterizedResGrpCount)
                PRINT (@AvailableParameterizedResGrpCount)
                RETURN
            END

        END
    ELSE IF @ParamterCondationIds IS NOT NULL
        BEGIN

            WITH CondationParamterIds AS (
                SELECT CAST([value] AS UNIQUEIDENTIFIER) AS Id
                FROM STRING_SPLIT(@ParamterCondationIds, ',')
            ),
            RequiredParameterValues AS (
                SELECT
                    PC.new_parameter,
                    ss.[value] AS RequiredValue,
                    PC.new_indv_parameter_condtionId
                FROM
                    new_servicecondationgroup SCG
                INNER JOIN
                    new_indv_parameter_condtion_group CG
                    ON SCG.new_condationgroup = CG.new_indv_parameter_condtion_groupId
                    AND SCG.new_type = 1000
                    AND SCG.new_service = @ServiceId
                INNER JOIN
                    new_indv_parameter_condtion PC
                    ON CG.new_indv_parameter_condtion_groupId = PC.new_parameter_condition_group
                    AND PC.new_indv_parameter_condtionId IN (SELECT Id FROM CondationParamterIds)
                LEFT JOIN
                    new_indv_baseparameter_condtion BPC
                    ON BPC.new_indv_baseparameter_condtionId = PC.new_baseparameter_condtion
                CROSS APPLY
                    STRING_SPLIT(ISNULL(BPC.new_value, PC.new_value), ',') ss
            ),
            FilteredResources AS (
                SELECT
                    R.new_rvresourcegroup,
                    RP.new_rvresource,
                    COUNT(DISTINCT RPV.new_indv_parameter_condtionId) AS MatchedConditionCount
                FROM
                    RequiredParameterValues RPV
                INNER JOIN
                    new_rvresourceparameter RP
                    ON RPV.new_parameter = RP.new_rvparameter
                    AND RPV.RequiredValue = RP.new_value
                INNER JOIN
                    new_rvresource R
                    ON RP.new_rvresource = R.new_rvresourceId
                GROUP BY
                    R.new_rvresourcegroup,
                    RP.new_rvresource
                HAVING
                    COUNT(DISTINCT RPV.new_indv_parameter_condtionId) = (SELECT COUNT(DISTINCT Id) FROM CondationParamterIds)
            )
            INSERT INTO #ResourcesWithChosenParameters (ResourceGroupId, ResourceId)
            SELECT new_rvresourcegroup, new_rvresource
            FROM FilteredResources;

            IF (SELECT COUNT(*) FROM #ResourcesWithChosenParameters) < @count
                RETURN;

        END


    INSERT INTO #TempServiceDays
    SELECT DISTINCT s.columnA
    FROM dbo.SplitToRows(@ServiceDays + ',', ',') s
    WHERE
    @RegionWeekDays IS NULL
    OR CHARINDEX(s.columnA, @RegionWeekDays) > 0;


    WITH CalDays
    AS (SELECT [DATE],
               [DayName]
        FROM
        (
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[DailyAvailableDatesWithOccurence](@StartDate, @EndDate, @ServiceDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 0
            UNION ALL
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[WeeklyAvailableDatesWithOccurence](@StartDate, @EndDate, @SelectedDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 1
            UNION ALL
            SELECT [DATE],
                   [DayName]
            FROM [dbo].[MonthlyAvailableDatesWithOccurence](
                                                               @StartDate,
                                                               @EndDate,
                                                               @ServiceDays,
                                                               @RecEvery,
                                                               @DayNum,
                                                               @Occurrence
                                                           )
            WHERE @RecurrenceType = 2
        ) AS Combined )


    INSERT INTO #TempCalendarDates
    SELECT [DATE],
           [DayName],
           CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, CalDays.[Date]), CAST(@FromTime AS DATETIME2)) AS DATETIME2) AS FromTime,
           DATEADD(
                      DAY,
                      IIF(@ToTime < @FromTime, 1, 0),
                      CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, CalDays.[Date]), CAST(@ToTime AS DATETIME2)) AS DATETIME2)
                  ) AS ToTime
    FROM CalDays;

    SELECT @MinDate = MIN([Date]),
           @MaxDate = MAX([Date])
    FROM #TempCalendarDates;



    IF (@ServiceResGrpCount > 0)
    BEGIN
        WITH RelationDefinitions
        AS (SELECT new_rvrelationdefinition.new_rvresourcegroup,
                   new_rvrelationtype.new_schemaname,
                   new_rvparameter.new_rvparameterId,
                   new_rvresourcegroup.new_name RSGroupName
            FROM new_rvrelationdefinition
                INNER JOIN new_rvrelationtype
                    ON new_rvrelationdefinition.new_rvrelationtype = new_rvrelationtype.new_rvrelationtypeId
                INNER JOIN new_rvresourcegroup
                    ON new_rvresourcegroup.new_rvresourcegroupId = new_rvrelationdefinition.new_rvresourcegroup
                LEFT OUTER JOIN new_rvparameter
                    ON new_rvparameter.new_type = 2
                       AND new_rvparameter.new_rvresourcegroup = new_rvrelationdefinition.new_rvresourcegroup
                       AND new_rvparameter.new_typeschemaname = new_rvrelationtype.new_schemaname
            WHERE new_rvrelationdefinition.new_rvservice = @ServiceId)
            ,
        ParameterConditions AS (
            SELECT
            conditionGrp.new_name conditionGrpName,
            ParameterCondition.new_name paramConditionName,
            ParameterCondition.new_parameter parameterId,
            operator.new_value operator,
            ParameterCondition.new_value [Value]
            FROM
            new_indv_parameter_condtion_group conditionGrp
            INNER JOIN new_indv_parameter_condtion ParameterCondition
            ON conditionGrp.new_indv_parameter_condtion_groupId = ParameterCondition.new_parameter_condition_group
        INNER Join new_servicecondationgroup as scg
            ON conditionGrp.new_indv_parameter_condtion_groupId = scg.new_condationgroup
            AND scg.new_service = @ServiceId
            INNER JOIN new_parameteroperator operator
            ON operator.new_parameteroperatorId = ParameterCondition.new_operator
            where  scg.new_type = 1001
        ),
        Resources
        AS (
            SELECT new_rvresource.new_name,
                   RelationParam.new_rvparameter,
                   RelationParam.new_name [parameterName],
                   new_rvresource.new_rvresourceId,
                   new_rvresource.new_rvresourcegroup,
                   new_rvresourcegroup.new_name AS RSGroupName,
                   new_rvresource.new_capacity,
                   RelationDefinitions.new_schemaname AS RelationType,
                   RelationParam.new_value RelationValue,
                   RSCalender.new_availabilitystartdate CalenderStartDate,
                   RSCalender.new_availabilityenddate CalenderEndDate,
                   RSCalender.new_maxworkinghoursperday MaxWorkingHours,
                   RSCalender.new_weekdays CalenderTimeSlotsDays
            FROM new_rvresource
                INNER JOIN new_rvresourcegroup
                    ON new_rvresourcegroup.new_rvresourcegroupId = new_rvresource.new_rvresourcegroup
                INNER JOIN #TempServiceResourceGroups
                    ON new_rvresource.new_rvresourcegroup = #TempServiceResourceGroups.rvresourcegroupId
                LEFT OUTER JOIN RelationDefinitions
                    ON new_rvresource.new_rvresourcegroup = RelationDefinitions.new_rvresourcegroup
                LEFT OUTER JOIN new_rvresourceparameter RelationParam
                    ON RelationParam.new_rvresource = new_rvresource.new_rvresourceId
                       AND RelationParam.new_rvparameter = RelationDefinitions.new_rvparameterId
                LEFT OUTER JOIN new_regionresource
                    ON new_regionresource.new_resource = new_rvresource.new_rvresourceId
                LEFT OUTER JOIN #ResourcesWithChosenParameters
                    ON new_rvresource.new_rvresourcegroup = ResourceGroupId
                OUTER APPLY
            (
                SELECT new_rvresourcecalendar.new_availabilitystartdate,
                       new_rvresourcecalendar.new_availabilityenddate,
                       new_rvresourcecalendar.new_maxworkinghoursperday,
                       timeslot.new_weekdays
                FROM new_rvresourcecalendar
                    LEFT OUTER JOIN new_resourcecalendartimeslot
                        ON new_rvresourcecalendar.new_islimitedtotimeslot = 1
                           AND new_rvresourcecalendar.new_rvresourcecalendarId = new_resourcecalendartimeslot.new_resourcecalendar
                    LEFT OUTER JOIN new_timeslot timeslot
                        ON new_resourcecalendartimeslot.new_timeslot = timeslot.new_timeslotId
                    LEFT OUTER JOIN #ResourcesWithChosenParameters
                        ON new_rvresource.new_rvresourcegroup = #ResourcesWithChosenParameters.ResourceGroupId
                WHERE
                    (
                        (
                            #ResourcesWithChosenParameters.ResourceGroupId IS NULL
                            AND #ResourcesWithChosenParameters.ResourceId IS NULL
                        )
                        OR
                        (
                            #ResourcesWithChosenParameters.ResourceGroupId IS NOT NULL
                            AND #ResourcesWithChosenParameters.ResourceId = new_rvresource.new_rvresourceId
                        )
                    )
                    AND
                    (
                        @ContactId IS NULL
                        OR @ContactId = '00000000-0000-0000-0000-000000000000'
                        OR NOT EXISTS (
                            SELECT 1
                            FROM new_contactblockresource blocklist
                            WHERE blocklist.new_resource = new_rvresource.new_rvresourceId
                            AND blocklist.new_customer = @ContactId
                        )
                    )
                    AND new_rvresourcecalendar.new_rvresource = new_rvresource.new_rvresourceId
                    AND
                    (
                        new_rvresourcecalendar.new_islimitedtotimeslot = 0
                        OR
                        (
                            new_rvresourcecalendar.new_islimitedtotimeslot = 1
                            AND timeslot.new_timeslotId IS NOT NULL
                            AND CAST(timeslot.new_startingtime AS TIME) <= CAST(@FromTime AS TIME)
                            AND CAST(timeslot.new_endingtime AS TIME) >= CAST(@ToTime AS TIME)
                        )
                    )
            ) AS RSCalender
            WHERE (new_rvresource.new_serviceprovider = @ServiceProvider)
                  AND
                  (
                    (
                        @ChosenParameters IS NULL
                        OR NOT EXISTS
                        (
                            SELECT 1
                            FROM #ChosenParametersTable CPT
                            WHERE CPT.ResourceGroupId = new_rvresource.new_rvresourcegroup
                        )
                        OR new_rvresource.new_rvresourceId IN
                        (
                            SELECT R.ResourceId FROM #ResourcesWithChosenParameters R
                        )
                    )
                    AND
                    (
                        Not Exists (
                            SELECT 1
                            FROM #ResourcesWithChosenParameters
                            where #ResourcesWithChosenParameters.ResourceGroupId = new_rvresource.new_rvresourcegroup
                        )
                        OR
                        (
                            (
                                Not Exists(select 1 from #ResourcesWithChosenParameters)
                                OR
                                Exists (
                                    select 1 from #ResourcesWithChosenParameters
                                    where new_rvresource.new_rvresourceId = #ResourcesWithChosenParameters.ResourceId
                                )
                            )
                            AND
                            (
                                Not Exists(select 1 from ParameterConditions)
                                OR
                                EXISTS (
                                    SELECT 1
                                    FROM ParameterConditions pc
                                    INNER JOIN new_rvresourceparameter rp2
                                        ON rp2.new_rvparameter = pc.parameterId
                                        AND rp2.new_rvresource = new_rvresource.new_rvresourceId
                                    WHERE
                                        (
                                            (pc.operator = '=' AND rp2.new_value = pc.[Value])
                                            OR
                                            (pc.operator = '<>' AND rp2.new_value <> pc.[Value])
                                            OR
                                            (
                                                pc.operator = 'IN'
                                                AND EXISTS (
                                                    SELECT 1
                                                    FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                )
                                            )
                                            OR
                                            (
                                                pc.operator = 'NOT IN'
                                                AND NOT EXISTS (
                                                    SELECT 1
                                                    FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                )
                                            )
                                        )
                                )
                            )
                        )
                    )
                  )
                  AND
                  (
                      (new_rvresource.new_islimitedtoregion IS NULL)
                      OR (new_rvresource.new_islimitedtoregion != 1)
                      OR (new_regionresource.new_region = @RegionId)
                  )

        ),

             ResourcesWithDates
        AS (SELECT Resources.*,
                   RequestedDates.*
            FROM Resources
                CROSS JOIN #TempServiceDays AS ServiceDays
                INNER JOIN #TempCalendarDates RequestedDates
                    ON RequestedDates.DayName = ServiceDays.DayName
            WHERE Resources.CalenderStartDate <= RequestedDates.DATE
                  AND Resources.CalenderEndDate >= RequestedDates.DATE
                  AND
                  (
                      Resources.CalenderTimeSlotsDays IS NULL
                      OR CHARINDEX(ServiceDays.[DayName], Resources.CalenderTimeSlotsDays) > 0
                  )),
             AvailableResourcesWithDates
        AS (SELECT DISTINCT
                   ResourcesWithDates.DATE,
                   ResourcesWithDates.DayName,
                   ResourcesWithDates.new_name,
                   ResourcesWithDates.new_rvresourcegroup,
                   ResourcesWithDates.RSGroupName,
                   ResourcesWithDates.new_rvresourceId,
                   ResourcesWithDates.RelationType,
                   ResourcesWithDates.RelationValue,
                   ISNULL(workedHours, 0) workedHours,
                   new_capacity - ISNULL(reservedQuantity, 0) AvailableQuantity
            FROM ResourcesWithDates
                -- parity: match Resources SP by removing resources whose
                -- stopped-days interval overlaps the requested slot.
                LEFT JOIN new_resourcestoppeddays resourcestoppeddays
                    ON ResourcesWithDates.new_rvresourceId = resourcestoppeddays.new_resource
                OUTER APPLY
            (
                SELECT ResourcesWithDates.new_rvresourceId,
                       SUM(reservationresource.new_quantity) AS reservedQuantity,
                       SUM(new_timeslot.new_hours) AS workedHours
                FROM new_reservation reservation
                    INNER JOIN new_reservationresource reservationresource
                        ON reservation.new_reservationId = reservationresource.new_reservation
                    INNER JOIN new_timeslot
                        ON new_timeslot.new_timeslotId = reservation.new_timeslot
                WHERE ResourcesWithDates.new_rvresourceId = reservationresource.new_rvresource
                      AND ResourcesWithDates.DATE = CAST(ResourcesWithDates.FromTime AS DATE)
                      AND
                        (
                            (
                                DATEADD(
                                    MINUTE,
                                    -ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvstarttime
                                ) >= ResourcesWithDates.FromTime
                                AND
                                DATEADD(
                                    MINUTE,
                                    -ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvstarttime
                                ) <= ResourcesWithDates.ToTime
                            )
                            OR
                            (
                                DATEADD(
                                    MINUTE,
                                    ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvendtime
                                ) >= ResourcesWithDates.FromTime
                                AND
                                DATEADD(
                                    MINUTE,
                                    ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvendtime
                                ) <= ResourcesWithDates.ToTime
                            )
                            OR
                            (
                                DATEADD(
                                    MINUTE,
                                    -ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvstarttime
                                ) <= ResourcesWithDates.FromTime
                                AND
                                DATEADD(
                                    MINUTE,
                                    ISNULL(new_timeslot.new_laboroffset, 0),
                                    reservation.new_rvendtime
                                ) >= ResourcesWithDates.ToTime
                            )
                        )

            ) AS resourceReservations
            WHERE ISNULL(workedHours, 0) + @Hours <= MaxWorkingHours
                  AND new_capacity > ISNULL(reservedQuantity, 0)
                  AND
                  (
                      (
                          resourcestoppeddays.new_startstoppingdate IS NULL
                          AND resourcestoppeddays.new_endstoppingdate IS NULL
                      )
                      OR (resourcestoppeddays.new_endstoppingdate < ResourcesWithDates.FromTime)
                      OR (resourcestoppeddays.new_startstoppingdate > ResourcesWithDates.ToTime)
                  ))
            ,

             ResourceRelations
        AS (SELECT DISTINCT
                   RelationType,
                   RelationValue
            FROM Resources),
             RelationDefinitionsCrossData
        AS (SELECT RelationDefinitions.new_rvresourcegroup RSGroup,
                   RelationType,
                   RelationValue,
                   RSGroupName
            FROM RelationDefinitions
                INNER JOIN ResourceRelations
                    ON ResourceRelations.RelationType = RelationDefinitions.new_schemaname),
             AvaliableResourcesWithRelations
        AS (SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
                   ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
                   ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
                   ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
                   ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
                   Resources.DATE
            FROM AvailableResourcesWithDates Resources
                FULL OUTER JOIN RelationDefinitionsCrossData
                    ON (
                           RelationDefinitionsCrossData.RelationType = Resources.RelationType
                           OR
                           (
                               Resources.RelationType IS NULL
                               AND RelationDefinitionsCrossData.RelationType IS NULL
                           )
                       )
                       AND
                       (
                           RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                           OR
                           (
                               Resources.RelationValue IS NULL
                               AND RelationDefinitionsCrossData.RelationValue IS NULL
                           )
                       )
                       AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
            WHERE AvailableQuantity IS NOT NULL
            UNION ALL
            SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
                   ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
                   ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
                   ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
                   ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
                   DistinctDates.DATE
            FROM AvailableResourcesWithDates Resources
                FULL OUTER JOIN RelationDefinitionsCrossData
                    ON (
                           RelationDefinitionsCrossData.RelationType = Resources.RelationType
                           OR
                           (
                               Resources.RelationType IS NULL
                               AND RelationDefinitionsCrossData.RelationType IS NULL
                           )
                       )
                       AND
                       (
                           RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                           OR
                           (
                               Resources.RelationValue IS NULL
                               AND RelationDefinitionsCrossData.RelationValue IS NULL
                           )
                       )
                       AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
                CROSS JOIN #TempCalendarDates DistinctDates
            WHERE AvailableQuantity IS NULL)
             ,AvaliableResourcesGroupedByResGroupAndRelation
        AS (SELECT new_rvresourcegroup,
                   RelationType,
                   RelationValue,
                   RSGroupName,
                   DATE,
                   SUM(AvailableQuantity) AS AvailableQuantity
            FROM AvaliableResourcesWithRelations
            GROUP BY DATE,
                     new_rvresourcegroup,
                     RelationType,
                     RelationValue,
                     RSGroupName)


             ,MinQuantityForByRelation

        AS (SELECT RelationType,
                   RelationValue,
                   DATE,
                   MIN(ISNULL(AvailableQuantity, 0)) AS MinQuantityForRSGroup
            FROM AvaliableResourcesGroupedByResGroupAndRelation
            WHERE RelationType IS NOT NULL
            GROUP BY DATE,
                     RelationType,
                     RelationValue),
             MinAvaliableQuantityByResourceGroupAndRelation
        AS (SELECT AvailableRes.DATE,
                   AvailableRes.new_rvresourcegroup,
                   AvailableRes.RelationType,
                   AvailableRes.RelationValue,
                   AvailableRes.RSGroupName,
                   MinQuantityForRSGroup,
                   AvailableQuantity av,
                   ISNULL(MinQuantityForRSGroup, AvailableQuantity) AS MinAvailableQuantity
            FROM AvaliableResourcesGroupedByResGroupAndRelation AvailableRes
                LEFT OUTER JOIN MinQuantityForByRelation
                    ON MinQuantityForByRelation.RelationType = AvailableRes.RelationType
                       AND
                       (
                           MinQuantityForByRelation.RelationValue = AvailableRes.RelationValue
                           OR
                           (
                               MinQuantityForByRelation.RelationValue IS NULL
                               AND AvailableRes.RelationValue IS NULL
                           )
                       )
                       AND
                       (
                           MinQuantityForByRelation.DATE = AvailableRes.DATE
                           OR MinQuantityForByRelation.DATE IS NULL
                       )),
             MinAvailableResourceGroup
        AS (SELECT DATE,
                   new_rvresourcegroup,
                   RSGroupName,
                   SUM(MinAvailableQuantity) AS AvailableQuantity
            FROM MinAvaliableQuantityByResourceGroupAndRelation
            WHERE DATE IS NOT NULL
            GROUP BY DATE,
                     new_rvresourcegroup,
                     RSGroupName),
             ServiceResourceGroupAvailability
        AS (SELECT DATENAME(WEEKDAY, [Date]) AS DayName,
                   DATE,
                   MinAvailableResourceGroup.new_rvresourcegroup,
                   RSGroupName,
                   MinAvailableResourceGroup.AvailableQuantity,
                   #TempServiceResourceGroups.RequiredQuantity,
                   IIF(MinAvailableResourceGroup.AvailableQuantity >= #TempServiceResourceGroups.RequiredQuantity, 1, 0) AS IsAvailable
            FROM MinAvailableResourceGroup
                INNER JOIN #TempServiceResourceGroups
                    ON #TempServiceResourceGroups.rvresourcegroupId = MinAvailableResourceGroup.new_rvresourcegroup)
        SELECT *
        INTO #TempServiceResourceGroupAvailability
        FROM ServiceResourceGroupAvailability;


        WITH DateAvailability AS
        (
            SELECT
                [Date],
                DATENAME(WEEKDAY, [Date]) AS DayName,
                MIN(IsAvailable) AS OccurrenceAvailability,
                COUNT(CASE WHEN IsAvailable = 1 THEN 1 END) AS AvailableCount
            FROM #TempServiceResourceGroupAvailability
            GROUP BY [Date], DATENAME(WEEKDAY, [Date])
        )
        ,
        VacationDates AS
        (
            SELECT [official-vacation].new_date AS Date
            FROM new_rvservice AS service
            INNER JOIN new_servicevacany AS [service-vacation]
                ON service.new_rvserviceId = [service-vacation].new_service
            INNER JOIN new_officialvacancy AS [official-vacation]
                ON [official-vacation].new_officialvacancyId = [service-vacation].new_officialvacancy
            WHERE service.new_rvserviceId = @ServiceId
        ),
        DateAvailabilityWithoutVacations AS(
        SELECT *
        FROM DateAvailability
        WHERE [Date] NOT IN (SELECT Date FROM VacationDates)
        ),
        FirstWeekDaysCalender
        AS(
            SELECT [DATE],[DayName]
            FROM [dbo].[WeeklyAvailableDatesWithOccurence](@StartDate, @EndDate, @SelectedDays, 1 , 1 )
            WHERE @RecurrenceType = 1
        ),
        FirstWeekAvailableDays
        AS(
            SELECT DATE , DayName from FirstWeekDaysCalender
            INTERSECT
            SELECT DATE , DayName from DateAvailabilityWithoutVacations
        )
        ,
        FilteredDateAvailabilityWithoutVacations
        As(
            select * from DateAvailabilityWithoutVacations
            where DateAvailabilityWithoutVacations.DayName in (
                select DayName from FirstWeekAvailableDays
            )
        ),
      ConsistentDays
        AS (SELECT DayName,
                   CASE
                       WHEN MIN(AvailableCount) = MAX(AvailableCount)
                            AND MIN(AvailableCount) =
                            (
                                SELECT COUNT(*)FROM #TempServiceResourceGroups
                            ) THEN
                           1
                       ELSE
                           0
                   END AS OccurrenceAvailability,
                   MIN(AvailableCount) AS ConsistentAvailableCount
            FROM FilteredDateAvailabilityWithoutVacations
            GROUP BY DayName
            HAVING MIN(AvailableCount) = MAX(AvailableCount)
                   AND MIN(AvailableCount) =
                   (
                       SELECT COUNT(*)FROM #TempServiceResourceGroups
                   ))

        SELECT DISTINCT
               DayName,
               OccurrenceAvailability
        INTO #TempFinalResult
        FROM ConsistentDays;


        IF @RecurrenceType = 1
        BEGIN
            SELECT TOP (1)
                   OccurrenceAvailability,
                   STUFF(
                   (
                       SELECT ',' + DayName FROM #TempFinalResult FOR XML PATH('')
                   ),
                   1,
                   1,
                   ''
                        ) AS AvailableDays
            FROM #TempFinalResult;
        END
        ELSE
        BEGIN
            SELECT DayName,
                   DATE,
                   MIN(IsAvailable) IsAvailable
            FROM #TempServiceResourceGroupAvailability
            GROUP BY DATE,
                     DayName
            ORDER BY DATE
        END

    END
    ELSE
    BEGIN

        IF @RecurrenceType = 1
        BEGIN
            SELECT TOP (1)
                   1 AS OccurrenceAvailability,
                   STUFF(
                   (
                       SELECT DISTINCT ',' + DayName FROM #TempCalendarDates FOR XML PATH('')
                   ),
                   1,
                   1,
                   ''
                        ) AS AvailableDays
            FROM #TempCalendarDates;
        END
        ELSE
        BEGIN
            SELECT DayName,
                   DATE,
                   1 AS IsAvailable
            FROM #TempCalendarDates
        END
    END

END;
GO



/****** Object:  StoredProcedure [dbo].[GetHourlyAvailabilityReportV01]    Script Date: 9/8/2026 2:02:08 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetHourlyAvailabilityReportV01]
(
    @TimeSlotId            UNIQUEIDENTIFIER,
    @ReccurrenceOptionId   UNIQUEIDENTIFIER,
    @ServiceId             UNIQUEIDENTIFIER,
    @RegionId              UNIQUEIDENTIFIER,
    @ContactId             UNIQUEIDENTIFIER = NULL,
    @ServiceProvider       UNIQUEIDENTIFIER = '7a85433b-2490-4c00-bfed-2816565ff459',
    @StartDate             DATETIME,
    @EndDate               DATETIME = NULL,
    @Occurrence            INT = NULL,
    @Count                 INT,
    @SelectedDays          NVARCHAR(80) = NULL,
    @ChosenParameters      NVARCHAR(MAX) = NULL,
    @ParamterCondationIds  NVARCHAR(MAX) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------------------------------
    -- Variables (engine + report)
    --------------------------------------------------------------------------------
    DECLARE @ServiceDays NVARCHAR(80);
    DECLARE @FromTime TIME;
    DECLARE @ToTime TIME;
    DECLARE @Hours INT;
    DECLARE @MinDate DATETIME;
    DECLARE @MaxDate DATETIME;
    DECLARE @RecEvery INT;
    DECLARE @DayNum INT;
    DECLARE @RecurrenceType INT;
    DECLARE @ServiceResGrpCount INT = 0;
    DECLARE @ParameterizedResGrpCount INT;
    DECLARE @AvailableParameterizedResGrpCount INT;

    -- Report control variables
    DECLARE @IsValid BIT = 1;
    DECLARE @ReasonCode INT = 0;
    DECLARE @ReasonAr NVARCHAR(300) = NULL;
    DECLARE @ReasonEn NVARCHAR(300) = NULL;

    --------------------------------------------------------------------------------
    -- Temp tables
    --------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#TempCalendarDates') IS NOT NULL DROP TABLE #TempCalendarDates;
    IF OBJECT_ID('tempdb..#TempServiceDays') IS NOT NULL DROP TABLE #TempServiceDays;
    IF OBJECT_ID('tempdb..#TempServiceResourceGroups') IS NOT NULL DROP TABLE #TempServiceResourceGroups;
    IF OBJECT_ID('tempdb..#ChosenParametersTable') IS NOT NULL DROP TABLE #ChosenParametersTable;
    IF OBJECT_ID('tempdb..#ResourcesWithChosenParameters') IS NOT NULL DROP TABLE #ResourcesWithChosenParameters;
    IF OBJECT_ID('tempdb..#TempServiceResourceGroupAvailability') IS NOT NULL DROP TABLE #TempServiceResourceGroupAvailability;

    CREATE TABLE #TempCalendarDates
    (
        [Date] DATETIME,
        [DayName] NVARCHAR(50),
        [FromTime] DATETIME2,
        [ToTime] DATETIME2
    );

    CREATE TABLE #TempServiceDays
    (
        [DayName] NVARCHAR(20)
    );

    CREATE TABLE #TempServiceResourceGroups
    (
        rvresourcegroupId UNIQUEIDENTIFIER,
        RequiredQuantity INT
    );

    CREATE TABLE #ChosenParametersTable
    (
        ResourceGroupId UNIQUEIDENTIFIER,
        ParameterId UNIQUEIDENTIFIER,
        Value NVARCHAR(100)
    );

    CREATE TABLE #ResourcesWithChosenParameters
    (
        ResourceId UNIQUEIDENTIFIER,
        ResourceGroupId UNIQUEIDENTIFIER
    );

    -- Created up-front (not via SELECT INTO) so the final report block can always
    -- read from it even when we jump straight to the reason output.
    CREATE TABLE #TempServiceResourceGroupAvailability
    (
        DayName NVARCHAR(50),
        [Date] DATETIME,
        new_rvresourcegroup UNIQUEIDENTIFIER NULL,
        RSGroupName NVARCHAR(200),
        AvailableQuantity INT,
        RequiredQuantity INT,
        IsAvailable INT
    );

    --------------------------------------------------------------------------------
    -- Timeslot data
    --------------------------------------------------------------------------------
    SELECT @FromTime = timeslot.new_startingtime,
           @ToTime = timeslot.new_endingtime,
           @Hours = timeslot.new_hours,
           @ServiceDays = timeslot.new_weekdays
    FROM new_timeslot timeslot
    WHERE new_timeslotId = @timeSlotId;

    --------------------------------------------------------------------------------
    -- Recurrence option data
    --------------------------------------------------------------------------------
    SELECT @RecEvery = RecOption.new_recevery,
           @DayNum = RecOption.new_daynumber,
           @RecurrenceType = RecOption.new_type
    FROM new_recurrenceoption RecOption
    WHERE new_recurrenceoptionId = @ReccurrenceOptionId;

    --------------------------------------------------------------------------------
    -- Region days
    --------------------------------------------------------------------------------
    DECLARE @RegionWeekDays NVARCHAR(80);

    SELECT TOP 1
        @RegionWeekDays = timeslot.new_weekdays
    FROM region
    INNER JOIN new_regiontimeslot rt
        ON region.regionId = rt.new_region
    INNER JOIN new_timeslot timeslot
        ON rt.new_timeslot = timeslot.new_timeslotId
    WHERE region.regionId = @RegionId
      AND region.new_islimited = 1;

    --------------------------------------------------------------------------------
    -- Validity check: timeslot + region   (was: early RETURN)
    --------------------------------------------------------------------------------
    IF dbo.IsServiceTimeSlotAndRegionValid(@ServiceId, @TimeSlotId, @RegionId, @FromTime, @ToTime) = 0
    BEGIN
        SELECT @IsValid = 0,
               @ReasonCode = 1,
               @ReasonEn = N'The selected timeslot or region is not valid for this service.',
               @ReasonAr = N'الفترة الزمنية أو المنطقة المختارة غير صالحة لهذه الخدمة.';
        GOTO Report;
    END;

    --------------------------------------------------------------------------------
    -- Service -> Resource Groups (with required quantity per group)
    --------------------------------------------------------------------------------
    WITH ServiceResourceGroups
    AS (SELECT serviceresource.new_rvresourcegroup AS rvresourcegroupId,
               serviceresource.new_quantity * @Count AS RequiredQuantity
        FROM new_rvserviceresource serviceresource
        WHERE serviceresource.new_rvservice = @ServiceId)
    INSERT INTO #TempServiceResourceGroups (rvresourcegroupId, RequiredQuantity)
    SELECT rvresourcegroupId, RequiredQuantity
    FROM ServiceResourceGroups;

    SELECT @ServiceResGrpCount = COUNT(rvresourcegroupId)
    FROM #TempServiceResourceGroups;

    --------------------------------------------------------------------------------
    -- Resolve eligible resources from chosen parameters OR condition ids
    --------------------------------------------------------------------------------
    IF @ChosenParameters IS NOT NULL
    BEGIN
        INSERT INTO #ChosenParametersTable
        SELECT *
        FROM dbo.ParseChosenParameters(@ChosenParameters);

        WITH ChosenParametersCount
        AS (SELECT ResourceGroupId,
                   COUNT(*) AS ParameterCount
            FROM #ChosenParametersTable
            GROUP BY ResourceGroupId)
        INSERT INTO #ResourcesWithChosenParameters
        SELECT resource.new_rvresourceId,
               resource.new_rvresourcegroup
        FROM new_rvresource [resource]
            INNER JOIN new_rvresourceparameter resourceparameter
                ON resourceparameter.new_rvresource = resource.new_rvresourceId
            INNER JOIN #ChosenParametersTable
                ON resource.new_rvresourcegroup = #ChosenParametersTable.ResourceGroupId
                AND resourceparameter.new_rvparameter = #ChosenParametersTable.ParameterId
                AND resourceparameter.new_value = #ChosenParametersTable.[Value]
            INNER JOIN ChosenParametersCount chosenCount
                ON #ChosenParametersTable.ResourceGroupId = chosenCount.ResourceGroupId
        GROUP BY resource.new_rvresourceId,
                 resource.new_rvresourcegroup
        HAVING COUNT(new_rvresourceId) = MAX(chosenCount.ParameterCount);

        SELECT @AvailableParameterizedResGrpCount = COUNT(DISTINCT ResourceGroupId)
        FROM #ResourcesWithChosenParameters Rwc
        WHERE Rwc.ResourceGroupId IN
        (
            SELECT DISTINCT ResourceGroupId FROM #ChosenParametersTable
        );

        SELECT @ParameterizedResGrpCount = COUNT(DISTINCT ResourceGroupId)
        FROM #ChosenParametersTable;

        IF (@ParameterizedResGrpCount != @AvailableParameterizedResGrpCount)
        BEGIN
            SELECT @IsValid = 0,
                   @ReasonCode = 2,
                   @ReasonEn = N'No resources match the chosen parameters for one or more required resource groups.',
                   @ReasonAr = N'لا توجد موارد مطابقة للمعايير المختارة في واحدة أو أكثر من مجموعات الموارد المطلوبة.';
            GOTO Report;
        END
    END
    ELSE IF @ParamterCondationIds IS NOT NULL
    BEGIN
        -- 1. chosen condition IDs
        WITH CondationParamterIds AS (
            SELECT CAST([value] AS UNIQUEIDENTIFIER) AS Id
            FROM STRING_SPLIT(@ParamterCondationIds, ',')
        ),
        -- 2. map condition IDs to required parameter values
        RequiredParameterValues AS (
            SELECT
                PC.new_parameter,
                ss.[value] AS RequiredValue,
                PC.new_indv_parameter_condtionId
            FROM
                new_servicecondationgroup SCG
            INNER JOIN
                new_indv_parameter_condtion_group CG
                ON SCG.new_condationgroup = CG.new_indv_parameter_condtion_groupId
                AND SCG.new_type = 1000
                AND SCG.new_service = @ServiceId
            INNER JOIN
                new_indv_parameter_condtion PC
                ON CG.new_indv_parameter_condtion_groupId = PC.new_parameter_condition_group
                AND PC.new_indv_parameter_condtionId IN (SELECT Id FROM CondationParamterIds)
            LEFT JOIN
                new_indv_baseparameter_condtion BPC
                ON BPC.new_indv_baseparameter_condtionId = PC.new_baseparameter_condtion
            CROSS APPLY
                STRING_SPLIT(ISNULL(BPC.new_value, PC.new_value), ',') ss
        ),
        -- 3. resources matching at least one value for *each* chosen condition
        FilteredResources AS (
            SELECT
                R.new_rvresourcegroup,
                RP.new_rvresource,
                COUNT(DISTINCT RPV.new_indv_parameter_condtionId) AS MatchedConditionCount
            FROM
                RequiredParameterValues RPV
            INNER JOIN
                new_rvresourceparameter RP
                ON RPV.new_parameter = RP.new_rvparameter
                AND RPV.RequiredValue = RP.new_value
            INNER JOIN
                new_rvresource R
                ON RP.new_rvresource = R.new_rvresourceId
            GROUP BY
                R.new_rvresourcegroup,
                RP.new_rvresource
            HAVING
                COUNT(DISTINCT RPV.new_indv_parameter_condtionId) = (SELECT COUNT(DISTINCT Id) FROM CondationParamterIds)
        )
        -- 4. final results
        INSERT INTO #ResourcesWithChosenParameters (ResourceGroupId, ResourceId)
        SELECT new_rvresourcegroup, new_rvresource
        FROM FilteredResources;

        IF (SELECT COUNT(*) FROM #ResourcesWithChosenParameters) < @count
        BEGIN
            SELECT @IsValid = 0,
                   @ReasonCode = 3,
                   @ReasonEn = N'Not enough resources match the selected nationality group for the requested count.',
                   @ReasonAr = N'عدد الموارد المطابقة لمجموعة الجنسيات المختارة أقل من العدد المطلوب.';
            GOTO Report;
        END
    END
    ELSE
    BEGIN
        SELECT @IsValid = 0,
               @ReasonCode = 4,
               @ReasonEn = N'No parameters or conditions were selected for this request.',
               @ReasonAr = N'لم يتم اختيار أي معايير أو شروط لهذا الطلب.';
        GOTO Report;
    END

    --------------------------------------------------------------------------------
    -- Service days (service weekdays intersected with region weekdays)
    --------------------------------------------------------------------------------
    INSERT INTO #TempServiceDays
    SELECT DISTINCT s.columnA
    FROM dbo.SplitToRows(@ServiceDays + ',', ',') s
    WHERE @RegionWeekDays IS NULL
       OR CHARINDEX(s.columnA, @RegionWeekDays) > 0;

    --------------------------------------------------------------------------------
    -- Calendar dates based on recurrence option (full recurrence honoured)
    --------------------------------------------------------------------------------
    WITH CalDays
    AS (SELECT [DATE], [DayName]
        FROM
        (
            SELECT [DATE], [DayName]
            FROM [dbo].[DailyAvailableDatesWithOccurence](@StartDate, @EndDate, @ServiceDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 0
            UNION ALL
            SELECT [DATE], [DayName]
            FROM [dbo].[WeeklyAvailableDatesWithOccurence](@StartDate, @EndDate, @SelectedDays, @RecEvery, @Occurrence)
            WHERE @RecurrenceType = 1
            UNION ALL
            SELECT [DATE], [DayName]
            FROM [dbo].[MonthlyAvailableDatesWithOccurence](@StartDate, @EndDate, @ServiceDays, @RecEvery, @DayNum, @Occurrence)
            WHERE @RecurrenceType = 2
        ) AS Combined)
    INSERT INTO #TempCalendarDates
    SELECT [DATE],
           [DayName],
           CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, CalDays.[Date]), CAST(@FromTime AS DATETIME2)) AS DATETIME2) AS FromTime,
           DATEADD(DAY,
                   IIF(@ToTime < @FromTime, 1, 0),
                   CAST(DATEADD(HOUR, DATEDIFF(HOUR, 0, CalDays.[Date]), CAST(@ToTime AS DATETIME2)) AS DATETIME2)) AS ToTime
    FROM CalDays;

    SELECT @MinDate = MIN([Date]),
           @MaxDate = MAX([Date])
    FROM #TempCalendarDates;

    --------------------------------------------------------------------------------
    -- Availability computation
    --------------------------------------------------------------------------------
    IF (@ServiceResGrpCount > 0)
    BEGIN
        ;WITH RelationDefinitions
        AS (SELECT new_rvrelationdefinition.new_rvresourcegroup,
                   new_rvrelationtype.new_schemaname,
                   new_rvparameter.new_rvparameterId,
                   new_rvresourcegroup.new_name RSGroupName
            FROM new_rvrelationdefinition
                INNER JOIN new_rvrelationtype
                    ON new_rvrelationdefinition.new_rvrelationtype = new_rvrelationtype.new_rvrelationtypeId
                INNER JOIN new_rvresourcegroup
                    ON new_rvresourcegroup.new_rvresourcegroupId = new_rvrelationdefinition.new_rvresourcegroup
                LEFT OUTER JOIN new_rvparameter
                    ON new_rvparameter.new_type = 2
                       AND new_rvparameter.new_rvresourcegroup = new_rvrelationdefinition.new_rvresourcegroup
                       AND new_rvparameter.new_typeschemaname = new_rvrelationtype.new_schemaname
            WHERE new_rvrelationdefinition.new_rvservice = @ServiceId),
        ParameterConditions AS (
            SELECT
                conditionGrp.new_name conditionGrpName,
                ParameterCondition.new_name paramConditionName,
                ParameterCondition.new_parameter parameterId,
                operator.new_value operator,
                ParameterCondition.new_value [Value]
            FROM
                new_indv_parameter_condtion_group conditionGrp
                INNER JOIN new_indv_parameter_condtion ParameterCondition
                    ON conditionGrp.new_indv_parameter_condtion_groupId = ParameterCondition.new_parameter_condition_group
                INNER JOIN new_servicecondationgroup AS scg
                    ON conditionGrp.new_indv_parameter_condtion_groupId = scg.new_condationgroup
                    AND scg.new_service = @ServiceId
                INNER JOIN new_parameteroperator operator
                    ON operator.new_parameteroperatorId = ParameterCondition.new_operator
            WHERE scg.new_type = 1001
        ),
        Resources
        AS (
            SELECT new_rvresource.new_name,
                   RelationParam.new_rvparameter,
                   RelationParam.new_name [parameterName],
                   new_rvresource.new_rvresourceId,
                   new_rvresource.new_rvresourcegroup,
                   new_rvresourcegroup.new_name AS RSGroupName,
                   new_rvresource.new_capacity,
                   RelationDefinitions.new_schemaname AS RelationType,
                   RelationParam.new_value RelationValue,
                   RSCalender.new_availabilitystartdate CalenderStartDate,
                   RSCalender.new_availabilityenddate CalenderEndDate,
                   RSCalender.new_maxworkinghoursperday MaxWorkingHours,
                   RSCalender.new_weekdays CalenderTimeSlotsDays
            FROM new_rvresource
                INNER JOIN new_rvresourcegroup
                    ON new_rvresourcegroup.new_rvresourcegroupId = new_rvresource.new_rvresourcegroup
                INNER JOIN #TempServiceResourceGroups
                    ON new_rvresource.new_rvresourcegroup = #TempServiceResourceGroups.rvresourcegroupId
                LEFT OUTER JOIN RelationDefinitions
                    ON new_rvresource.new_rvresourcegroup = RelationDefinitions.new_rvresourcegroup
                LEFT OUTER JOIN new_rvresourceparameter RelationParam
                    ON RelationParam.new_rvresource = new_rvresource.new_rvresourceId
                       AND RelationParam.new_rvparameter = RelationDefinitions.new_rvparameterId
                LEFT OUTER JOIN new_regionresource
                    ON new_regionresource.new_resource = new_rvresource.new_rvresourceId
                LEFT OUTER JOIN #ResourcesWithChosenParameters
                    ON new_rvresource.new_rvresourcegroup = ResourceGroupId
                OUTER APPLY
            (
                SELECT new_rvresourcecalendar.new_availabilitystartdate,
                       new_rvresourcecalendar.new_availabilityenddate,
                       new_rvresourcecalendar.new_maxworkinghoursperday,
                       timeslot.new_weekdays
                FROM new_rvresourcecalendar
                    LEFT OUTER JOIN new_resourcecalendartimeslot
                        ON new_rvresourcecalendar.new_islimitedtotimeslot = 1
                           AND new_rvresourcecalendar.new_rvresourcecalendarId = new_resourcecalendartimeslot.new_resourcecalendar
                    LEFT OUTER JOIN new_timeslot timeslot
                        ON new_resourcecalendartimeslot.new_timeslot = timeslot.new_timeslotId
                    LEFT OUTER JOIN #ResourcesWithChosenParameters
                        ON new_rvresource.new_rvresourcegroup = #ResourcesWithChosenParameters.ResourceGroupId
                WHERE
                    (
                        (
                            #ResourcesWithChosenParameters.ResourceGroupId IS NULL
                            AND #ResourcesWithChosenParameters.ResourceId IS NULL
                        )
                        OR
                        (
                            #ResourcesWithChosenParameters.ResourceGroupId IS NOT NULL
                            AND #ResourcesWithChosenParameters.ResourceId = new_rvresource.new_rvresourceId
                        )
                    )
                    AND
                    (
                        @ContactId IS NULL
                        OR @ContactId = '00000000-0000-0000-0000-000000000000'
                        OR NOT EXISTS (
                            SELECT 1
                            FROM new_contactblockresource blocklist
                            WHERE blocklist.new_resource = new_rvresource.new_rvresourceId
                            AND blocklist.new_customer = @ContactId
                        )
                    )
                    AND new_rvresourcecalendar.new_rvresource = new_rvresource.new_rvresourceId
                    AND
                    (
                        new_rvresourcecalendar.new_islimitedtotimeslot = 0
                        OR
                        (
                            new_rvresourcecalendar.new_islimitedtotimeslot = 1
                            AND timeslot.new_timeslotId IS NOT NULL
                            AND CAST(timeslot.new_startingtime AS TIME) <= CAST(@FromTime AS TIME)
                            AND CAST(timeslot.new_endingtime AS TIME) >= CAST(@ToTime AS TIME)
                        )
                    )
            ) AS RSCalender
            WHERE (new_rvresource.new_serviceprovider = @ServiceProvider)
                  AND
                  (
                    (
                        @ChosenParameters IS NULL
                        OR NOT EXISTS
                        (
                            SELECT 1
                            FROM #ChosenParametersTable CPT
                            WHERE CPT.ResourceGroupId = new_rvresource.new_rvresourcegroup
                        )
                        OR new_rvresource.new_rvresourceId IN
                        (
                            SELECT R.ResourceId FROM #ResourcesWithChosenParameters R
                        )
                    )
                    AND
                    (
                        Not Exists (
                            SELECT 1
                            FROM #ResourcesWithChosenParameters
                            WHERE #ResourcesWithChosenParameters.ResourceGroupId = new_rvresource.new_rvresourcegroup
                        )
                        OR
                        (
                            (
                                Not Exists(SELECT 1 FROM #ResourcesWithChosenParameters)
                                OR
                                Exists (
                                    SELECT 1 FROM #ResourcesWithChosenParameters
                                    WHERE new_rvresource.new_rvresourceId = #ResourcesWithChosenParameters.ResourceId
                                )
                            )
                            AND
                            (
                                Not Exists(SELECT 1 FROM ParameterConditions)
                                OR
                                EXISTS (
                                    SELECT 1
                                    FROM ParameterConditions pc
                                    INNER JOIN new_rvresourceparameter rp2
                                        ON rp2.new_rvparameter = pc.parameterId
                                        AND rp2.new_rvresource = new_rvresource.new_rvresourceId
                                    WHERE
                                        (
                                            (pc.operator = '=' AND rp2.new_value = pc.[Value])
                                            OR (pc.operator = '<>' AND rp2.new_value <> pc.[Value])
                                            OR (pc.operator = 'IN'
                                                AND EXISTS (
                                                    SELECT 1 FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                ))
                                            OR (pc.operator = 'NOT IN'
                                                AND NOT EXISTS (
                                                    SELECT 1 FROM STRING_SPLIT(pc.[Value], ',')
                                                    WHERE TRIM(value) = rp2.new_value
                                                ))
                                        )
                                )
                            )
                        )
                    )
                  )
                  AND
                  (
                      (new_rvresource.new_islimitedtoregion IS NULL)
                      OR (new_rvresource.new_islimitedtoregion != 1)
                      OR (new_regionresource.new_region = @RegionId)
                  )
        ),
        ResourcesWithDates
        AS (SELECT Resources.*,
                   RequestedDates.*
            FROM Resources
                CROSS JOIN #TempServiceDays AS ServiceDays
                INNER JOIN #TempCalendarDates RequestedDates
                    ON RequestedDates.DayName = ServiceDays.DayName
            WHERE Resources.CalenderStartDate <= RequestedDates.DATE
                  AND Resources.CalenderEndDate >= RequestedDates.DATE
                  AND
                  (
                      Resources.CalenderTimeSlotsDays IS NULL
                      OR CHARINDEX(ServiceDays.[DayName], Resources.CalenderTimeSlotsDays) > 0
                  )),
        AvailableResourcesWithDates
        AS (SELECT DISTINCT
                   ResourcesWithDates.DATE,
                   ResourcesWithDates.DayName,
                   ResourcesWithDates.new_name,
                   ResourcesWithDates.new_rvresourcegroup,
                   ResourcesWithDates.RSGroupName,
                   ResourcesWithDates.new_rvresourceId,
                   ResourcesWithDates.RelationType,
                   ResourcesWithDates.RelationValue,
                   ISNULL(workedHours, 0) workedHours,
                   new_capacity - ISNULL(reservedQuantity, 0) AvailableQuantity
            FROM ResourcesWithDates
                OUTER APPLY
            (
                SELECT ResourcesWithDates.new_rvresourceId,
                       SUM(reservationresource.new_quantity) AS reservedQuantity,
                       SUM(new_timeslot.new_hours) AS workedHours
                FROM new_reservation reservation
                    INNER JOIN new_reservationresource reservationresource
                        ON reservation.new_reservationId = reservationresource.new_reservation
                    INNER JOIN new_timeslot
                        ON new_timeslot.new_timeslotId = reservation.new_timeslot
                WHERE ResourcesWithDates.new_rvresourceId = reservationresource.new_rvresource
                      AND ResourcesWithDates.DATE = CAST(ResourcesWithDates.FromTime AS DATE)
                      AND
                        (
                            (
                                DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime) >= ResourcesWithDates.FromTime
                                AND DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime) <= ResourcesWithDates.ToTime
                            )
                            OR
                            (
                                DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime) >= ResourcesWithDates.FromTime
                                AND DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime) <= ResourcesWithDates.ToTime
                            )
                            OR
                            (
                                DATEADD(MINUTE, -ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvstarttime) <= ResourcesWithDates.FromTime
                                AND DATEADD(MINUTE, ISNULL(new_timeslot.new_laboroffset, 0), reservation.new_rvendtime) >= ResourcesWithDates.ToTime
                            )
                        )
            ) AS resourceReservations
            WHERE ISNULL(workedHours, 0) + @Hours <= MaxWorkingHours
                  AND new_capacity > ISNULL(reservedQuantity, 0)),
        ResourceRelations
        AS (SELECT DISTINCT RelationType, RelationValue FROM Resources),
        RelationDefinitionsCrossData
        AS (SELECT RelationDefinitions.new_rvresourcegroup RSGroup,
                   RelationType,
                   RelationValue,
                   RSGroupName
            FROM RelationDefinitions
                INNER JOIN ResourceRelations
                    ON ResourceRelations.RelationType = RelationDefinitions.new_schemaname),
        AvaliableResourcesWithRelations
        AS (SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
                   ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
                   ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
                   ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
                   ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
                   Resources.DATE
            FROM AvailableResourcesWithDates Resources
                FULL OUTER JOIN RelationDefinitionsCrossData
                    ON (
                           RelationDefinitionsCrossData.RelationType = Resources.RelationType
                           OR (Resources.RelationType IS NULL AND RelationDefinitionsCrossData.RelationType IS NULL)
                       )
                       AND
                       (
                           RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                           OR (Resources.RelationValue IS NULL AND RelationDefinitionsCrossData.RelationValue IS NULL)
                       )
                       AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
            WHERE AvailableQuantity IS NOT NULL
            UNION ALL
            SELECT ISNULL(new_rvresourcegroup, RelationDefinitionsCrossData.RSGroup) AS new_rvresourcegroup,
                   ISNULL(Resources.RelationType, RelationDefinitionsCrossData.RelationType) AS RelationType,
                   ISNULL(Resources.RSGroupName, RelationDefinitionsCrossData.RSGroupName) AS RSGroupName,
                   ISNULL(Resources.RelationValue, RelationDefinitionsCrossData.RelationValue) AS RelationValue,
                   ISNULL(AvailableQuantity, 0) AS AvailableQuantity,
                   DistinctDates.DATE
            FROM AvailableResourcesWithDates Resources
                FULL OUTER JOIN RelationDefinitionsCrossData
                    ON (
                           RelationDefinitionsCrossData.RelationType = Resources.RelationType
                           OR (Resources.RelationType IS NULL AND RelationDefinitionsCrossData.RelationType IS NULL)
                       )
                       AND
                       (
                           RelationDefinitionsCrossData.RelationValue = Resources.RelationValue
                           OR (Resources.RelationValue IS NULL AND RelationDefinitionsCrossData.RelationValue IS NULL)
                       )
                       AND RelationDefinitionsCrossData.RSGroup = new_rvresourcegroup
                CROSS JOIN #TempCalendarDates DistinctDates
            WHERE AvailableQuantity IS NULL),
        AvaliableResourcesGroupedByResGroupAndRelation
        AS (SELECT new_rvresourcegroup,
                   RelationType,
                   RelationValue,
                   RSGroupName,
                   DATE,
                   SUM(AvailableQuantity) AS AvailableQuantity
            FROM AvaliableResourcesWithRelations
            GROUP BY DATE, new_rvresourcegroup, RelationType, RelationValue, RSGroupName),
        MinQuantityForByRelation
        AS (SELECT RelationType,
                   RelationValue,
                   DATE,
                   MIN(ISNULL(AvailableQuantity, 0)) AS MinQuantityForRSGroup
            FROM AvaliableResourcesGroupedByResGroupAndRelation
            WHERE RelationType IS NOT NULL
            GROUP BY DATE, RelationType, RelationValue),
        MinAvaliableQuantityByResourceGroupAndRelation
        AS (SELECT AvailableRes.DATE,
                   AvailableRes.new_rvresourcegroup,
                   AvailableRes.RelationType,
                   AvailableRes.RelationValue,
                   AvailableRes.RSGroupName,
                   MinQuantityForRSGroup,
                   AvailableQuantity av,
                   ISNULL(MinQuantityForRSGroup, AvailableQuantity) AS MinAvailableQuantity
            FROM AvaliableResourcesGroupedByResGroupAndRelation AvailableRes
                LEFT OUTER JOIN MinQuantityForByRelation
                    ON MinQuantityForByRelation.RelationType = AvailableRes.RelationType
                       AND (MinQuantityForByRelation.RelationValue = AvailableRes.RelationValue
                            OR (MinQuantityForByRelation.RelationValue IS NULL AND AvailableRes.RelationValue IS NULL))
                       AND (MinQuantityForByRelation.DATE = AvailableRes.DATE
                            OR MinQuantityForByRelation.DATE IS NULL)),
        MinAvailableResourceGroup
        AS (SELECT DATE,
                   new_rvresourcegroup,
                   RSGroupName,
                   SUM(MinAvailableQuantity) AS AvailableQuantity
            FROM MinAvaliableQuantityByResourceGroupAndRelation
            WHERE DATE IS NOT NULL
            GROUP BY DATE, new_rvresourcegroup, RSGroupName),
        ServiceResourceGroupAvailability
        AS (SELECT DATENAME(WEEKDAY, [Date]) AS DayName,
                   DATE,
                   MinAvailableResourceGroup.new_rvresourcegroup,
                   RSGroupName,
                   MinAvailableResourceGroup.AvailableQuantity,
                   #TempServiceResourceGroups.RequiredQuantity,
                   IIF(MinAvailableResourceGroup.AvailableQuantity >= #TempServiceResourceGroups.RequiredQuantity, 1, 0) AS IsAvailable
            FROM MinAvailableResourceGroup
                INNER JOIN #TempServiceResourceGroups
                    ON #TempServiceResourceGroups.rvresourcegroupId = MinAvailableResourceGroup.new_rvresourcegroup)
        INSERT INTO #TempServiceResourceGroupAvailability
        (DayName, [Date], new_rvresourcegroup, RSGroupName, AvailableQuantity, RequiredQuantity, IsAvailable)
        SELECT DayName, DATE, new_rvresourcegroup, RSGroupName, AvailableQuantity, RequiredQuantity, IsAvailable
        FROM ServiceResourceGroupAvailability;
    END
    ELSE
    BEGIN
        -- Service has no resource groups: every generated date is unconstrained.
        INSERT INTO #TempServiceResourceGroupAvailability
        (DayName, [Date], new_rvresourcegroup, RSGroupName, AvailableQuantity, RequiredQuantity, IsAvailable)
        SELECT DISTINCT
               DayName,
               [Date],
               NULL,
               N'بدون قيود موارد / No resource constraints',
               0,
               0,
               1
        FROM #TempCalendarDates;
    END

    --------------------------------------------------------------------------------
    -- REPORT OUTPUT
    --------------------------------------------------------------------------------
    Report:

    -- [1] Header / summary
    SELECT @IsValid              AS IsValid,
           @ReasonCode           AS ReasonCode,
           @ReasonAr             AS ReasonAr,
           @ReasonEn             AS ReasonEn,
           @FromTime             AS FromTime,
           @ToTime               AS ToTime,
           @Hours                AS Hours,
           @RecurrenceType       AS RecurrenceType,
           @ServiceResGrpCount   AS ResourceGroupCount,
           @Count                AS RequestedCount,
           @MinDate              AS MinDate,
           @MaxDate              AS MaxDate;

    -- [2] Detail: one row per Date x Resource Group, with vacation + bilingual reason
    ;WITH Vac AS
    (
        SELECT [official-vacation].new_date AS VacDate
        FROM new_rvservice AS service
        INNER JOIN new_servicevacany AS [service-vacation]
            ON service.new_rvserviceId = [service-vacation].new_service
        INNER JOIN new_officialvacancy AS [official-vacation]
            ON [official-vacation].new_officialvacancyId = [service-vacation].new_officialvacancy
        WHERE service.new_rvserviceId = @ServiceId
    )
    SELECT
        a.[Date],
        a.DayName,
        a.new_rvresourcegroup                                          AS ResourceGroupId,
        a.RSGroupName,
        a.RequiredQuantity,
        a.AvailableQuantity,
        CASE WHEN v.VacDate IS NOT NULL THEN 0 ELSE a.IsAvailable END   AS IsAvailable,
        CAST(CASE WHEN v.VacDate IS NOT NULL THEN 1 ELSE 0 END AS BIT)  AS IsVacation,
        CASE
            WHEN v.VacDate IS NOT NULL              THEN N'إجازة رسمية'
            WHEN a.IsAvailable = 1                  THEN N'متاح'
            WHEN ISNULL(a.AvailableQuantity, 0) <= 0 THEN N'لا توجد موارد متاحة'
            ELSE                                         N'السعة غير كافية (المتاح ' + CAST(ISNULL(a.AvailableQuantity,0) AS NVARCHAR(10)) + N' من ' + CAST(a.RequiredQuantity AS NVARCHAR(10)) + N' مطلوب)'
        END                                                            AS ReasonAr,
        CASE
            WHEN v.VacDate IS NOT NULL              THEN 'Official vacation'
            WHEN a.IsAvailable = 1                  THEN 'Available'
            WHEN ISNULL(a.AvailableQuantity, 0) <= 0 THEN 'No available resources'
            ELSE                                         'Insufficient capacity (' + CAST(ISNULL(a.AvailableQuantity,0) AS VARCHAR(10)) + ' of ' + CAST(a.RequiredQuantity AS VARCHAR(10)) + ' required)'
        END                                                            AS ReasonEn
    FROM #TempServiceResourceGroupAvailability a
        LEFT JOIN Vac v
            ON CAST(v.VacDate AS DATE) = CAST(a.[Date] AS DATE)
    ORDER BY a.[Date], a.RSGroupName;

END;

GO
/****** Object:  StoredProcedure [dbo].[GetHourlyAvailabilityFaqCountsV01]    Script Date: 9/8/2026 2:03:17 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetHourlyAvailabilityFaqCountsV01]
(
    @ServiceId            UNIQUEIDENTIFIER,
    @RegionId             UNIQUEIDENTIFIER = NULL,
    @ParamterCondationIds NVARCHAR(MAX) = NULL,   -- nationality condition id(s), CSV
    @ServiceProvider      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#RequiredParamValues') IS NOT NULL DROP TABLE #RequiredParamValues;
    IF OBJECT_ID('tempdb..#NatResources') IS NOT NULL DROP TABLE #NatResources;

    --------------------------------------------------------------------------------
    -- Resolve required nationality values from the passed parameter_condition ids
    --------------------------------------------------------------------------------
    CREATE TABLE #RequiredParamValues
    (
        ConditionId UNIQUEIDENTIFIER,
        ParameterId UNIQUEIDENTIFIER,
        [Value]     NVARCHAR(200)
    );

    IF @ParamterCondationIds IS NOT NULL AND LTRIM(RTRIM(@ParamterCondationIds)) <> ''
    BEGIN
        ;WITH CondIds AS
        (
            SELECT TRY_CAST(LTRIM(RTRIM(value)) AS UNIQUEIDENTIFIER) AS Id
            FROM STRING_SPLIT(@ParamterCondationIds, ',')
            WHERE TRY_CAST(LTRIM(RTRIM(value)) AS UNIQUEIDENTIFIER) IS NOT NULL
        )
        INSERT INTO #RequiredParamValues (ConditionId, ParameterId, [Value])
        SELECT PC.new_indv_parameter_condtionId,
               PC.new_parameter,
               LTRIM(RTRIM(ss.value))
        FROM new_indv_parameter_condtion PC
            LEFT JOIN new_indv_baseparameter_condtion BPC
                ON BPC.new_indv_baseparameter_condtionId = PC.new_baseparameter_condtion
            CROSS APPLY STRING_SPLIT(ISNULL(BPC.new_value, PC.new_value), ',') ss
        WHERE PC.new_indv_parameter_condtionId IN (SELECT Id FROM CondIds);
    END

    DECLARE @CondCount INT = (SELECT COUNT(DISTINCT ConditionId) FROM #RequiredParamValues);

    -- resources that satisfy ALL passed conditions
    CREATE TABLE #NatResources (ResourceId UNIQUEIDENTIFIER PRIMARY KEY);

    IF @CondCount > 0
    BEGIN
        INSERT INTO #NatResources (ResourceId)
        SELECT rp.new_rvresource
        FROM new_rvresourceparameter rp
            INNER JOIN #RequiredParamValues rpv
                ON rpv.ParameterId = rp.new_rvparameter
                AND rpv.[Value] = rp.new_value
        GROUP BY rp.new_rvresource
        HAVING COUNT(DISTINCT rpv.ConditionId) = @CondCount;
    END

    --------------------------------------------------------------------------------
    -- Answers
    --------------------------------------------------------------------------------
    SELECT QuestionNo, QuestionAr, QuestionEn, Answer
    FROM
    (
        -- Q1
        SELECT 1 AS QuestionNo,
               N'هل يوجد موظفون مسجلون على مشروع الساعات؟ وكم عددهم؟' AS QuestionAr,
               N'Employees registered on the hourly project' AS QuestionEn,
               (
                   SELECT COUNT(res.new_rvresourceId)
                   FROM new_rvresource res
                       INNER JOIN new_indv_resource indvRes ON res.new_rvresourceId = indvRes.new_rvresource
                       INNER JOIN new_employee emp ON indvRes.new_indv_resourceId = emp.new_indvresource
               ) AS Answer

        UNION ALL
        -- Q2
        SELECT 2,
               N'موظفون مسجلون على مشروع الساعات وحالتهم (نشط على رأس العمل أو نشط في السكن)',
               N'Registered employees with status Active-Working or Active-Accommodation',
               (
                   SELECT COUNT(res.new_rvresourceId)
                   FROM new_rvresource res
                       INNER JOIN new_indv_resource indvRes ON res.new_rvresourceId = indvRes.new_rvresource
                       INNER JOIN new_employee emp ON indvRes.new_indv_resourceId = emp.new_indvresource
                       INNER JOIN new_employeestatus empStatus
                           ON emp.new_employeestatus = empStatus.new_employeestatusId
                           AND empStatus.new_code IN (102, 106)
               )

        UNION ALL
        -- Q3: active + required nationality
        SELECT 3,
               N'موظفون مسجلون على مشروع الساعات لـ الجنسية المطلوبة',
               N'Registered employees for the required nationality',
               (
                   SELECT COUNT(res.new_rvresourceId)
                   FROM new_rvresource res
                       INNER JOIN new_indv_resource indvRes ON res.new_rvresourceId = indvRes.new_rvresource
                       INNER JOIN new_employee emp ON indvRes.new_indv_resourceId = emp.new_indvresource
                       INNER JOIN new_employeestatus empStatus
                           ON emp.new_employeestatus = empStatus.new_employeestatusId
                           AND empStatus.new_code IN (102, 106)
                   WHERE (@ServiceProvider IS NULL OR res.new_serviceprovider = @ServiceProvider)
                         AND (@CondCount = 0 OR res.new_rvresourceId IN (SELECT ResourceId FROM #NatResources))
               )

        UNION ALL
        -- Q4: Q3 + serves the desired region
        SELECT 4,
               N'موظفون مسجلون على مشروع الساعات لـ الجنسية المطلوبة في المنطقة المطلوبة',
               N'Registered employees for the required nationality in the desired region',
               (
                   SELECT COUNT(res.new_rvresourceId)
                   FROM new_rvresource res
                       INNER JOIN new_indv_resource indvRes ON res.new_rvresourceId = indvRes.new_rvresource
                       INNER JOIN new_employee emp ON indvRes.new_indv_resourceId = emp.new_indvresource
                       INNER JOIN new_employeestatus empStatus
                           ON emp.new_employeestatus = empStatus.new_employeestatusId
                           AND empStatus.new_code IN (102, 106)
                   WHERE (@ServiceProvider IS NULL OR res.new_serviceprovider = @ServiceProvider)
                         AND (@CondCount = 0 OR res.new_rvresourceId IN (SELECT ResourceId FROM #NatResources))
                         AND (
                                 (res.new_islimitedtoregion IS NULL OR res.new_islimitedtoregion <> 1)
                                 OR EXISTS (SELECT 1 FROM new_regionresource rr
                                            WHERE rr.new_resource = res.new_rvresourceId
                                              AND rr.new_region = @RegionId)
                             )
               )

        UNION ALL
        -- Q5: car seats (capacity) serving the desired region
        SELECT 5,
               N'هل يوجد مقاعد سيارات تخدم المنطقة المطلوبة؟ (عدد المقاعد)',
               N'Car seats (capacity) serving the desired region',
               (
                   SELECT ISNULL(SUM(res.new_capacity), 0)
                   FROM new_rvresource res
                   WHERE res.new_rvresourceId IN (SELECT new_resource FROM new_car WHERE new_resource IS NOT NULL)
                         AND (@ServiceProvider IS NULL OR res.new_serviceprovider = @ServiceProvider)
                         AND (
                                 (res.new_islimitedtoregion IS NULL OR res.new_islimitedtoregion <> 1)
                                 OR EXISTS (SELECT 1 FROM new_regionresource rr
                                            WHERE rr.new_resource = res.new_rvresourceId
                                              AND rr.new_region = @RegionId)
                             )
               )

        UNION ALL
        -- Q6: Q4 + serves the required service
        SELECT 6,
               N'موظفون يخدمون الخدمة المطلوبة ولديهم الجنسية المطلوبة لـ المنطقة المطلوبة',
               N'Employees serving the required service, with the required nationality, for the desired region',
               (
                   SELECT COUNT(res.new_rvresourceId)
                   FROM new_rvresource res
                       INNER JOIN new_indv_resource indvRes ON res.new_rvresourceId = indvRes.new_rvresource
                       INNER JOIN new_employee emp ON indvRes.new_indv_resourceId = emp.new_indvresource
                       INNER JOIN new_employeestatus empStatus
                           ON emp.new_employeestatus = empStatus.new_employeestatusId
                           AND empStatus.new_code IN (102, 106)
                   WHERE (@ServiceProvider IS NULL OR res.new_serviceprovider = @ServiceProvider)
                         AND (@CondCount = 0 OR res.new_rvresourceId IN (SELECT ResourceId FROM #NatResources))
                         AND (
                                 (res.new_islimitedtoregion IS NULL OR res.new_islimitedtoregion <> 1)
                                 OR EXISTS (SELECT 1 FROM new_regionresource rr
                                            WHERE rr.new_resource = res.new_rvresourceId
                                              AND rr.new_region = @RegionId)
                             )
                         AND EXISTS (SELECT 1 FROM new_rvserviceresource sr
                                     WHERE sr.new_rvresourcegroup = res.new_rvresourcegroup
                                       AND sr.new_rvservice = @ServiceId)
               )
    ) AS Faq
    ORDER BY QuestionNo;

END;
GO

/****** Object:  StoredProcedure [dbo].[GetCandidateRefundedReservationsByContract]    Script Date: 9/8/2026 2:06:51 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetCandidateRefundedReservationsByContract]
    @ContractNumber NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        reservation.new_reservationId      AS ReservationId,
        reservation.new_name               AS ReservationNumber,
        reservation.new_rvstarttime        AS StartTime,
        reservation.new_rvendtime          AS EndTime,
        resource.new_name                  AS EmployeeName
    FROM new_reservation AS reservation
    INNER JOIN new_reservationresource AS [reservation-resource]
        ON reservation.new_reservationId = [reservation-resource].new_reservation
    INNER JOIN new_rvresource AS resource
        ON resource.new_rvresourceId = [reservation-resource].new_rvresource
    INNER JOIN new_rvresourcegroup AS [resource-group]
        ON [resource-group].new_rvresourcegroupId = resource.new_rvresourcegroup
    INNER JOIN new_rvserviceresource AS [service-resource-group]
        ON [service-resource-group].new_rvresourcegroup = [resource-group].new_rvresourcegroupId
       AND [service-resource-group].new_showdetails = 1
    INNER JOIN new_hcontract AS contract
        ON contract.new_hcontractId = reservation.new_hcontract
    WHERE contract.new_name = @ContractNumber
      AND reservation.statuscode IN (0);
END;

GO
/****** Object:  StoredProcedure [dbo].[GetAllSelectedHourlyPricingDetailsByIds_AppleView]    Script Date: 9/8/2026 2:08:12 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetAllSelectedHourlyPricingDetailsByIds_AppleView]
    @serviceIds NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SelectedServiceIds TABLE
    (
        serviceId UNIQUEIDENTIFIER
    );

    INSERT INTO @SelectedServiceIds (serviceId)
    SELECT TRY_CAST(value AS UNIQUEIDENTIFIER)
    FROM STRING_SPLIT(@serviceIds, ',')
    WHERE TRY_CAST(value AS UNIQUEIDENTIFIER) IS NOT NULL;

    SELECT
        shp.new_selectedhourlypricingId AS SelectedHourlyPricingId,
        shp.new_name AS DisplayNameEn,
        shp.new_namear AS DisplayNameAr,
        shp.new_name_appleview AS DisplayNameEn_appleview,
        shp.new_namear_appleview AS DisplayNameAr_appleview,

        shp.new_service AS ServiceId,
        s.new_code AS ServiceCode,

        shp.new_resourcecount AS EmployeeNumber,
        shp.new_weeklyvisits AS WeeklyVisits,
        shp.new_occurrence AS ContractDuration,

        shp.new_unitprice AS HourPrice,

        shp.new_freereservationcount AS FreeReservationCount,
        shp.new_no_visits AS TotalVisits,
        shp.new_packageprice AS packagePriceAfterPromotion,
        shp.new_promotionamount AS PromotionAmount,
        shp.new_timeslot AS TimeslotId,
        shp.new_recurrenceoption AS RecurrenceOptionId,
        shp.new_pricelist AS PricingId,
        shp.new_vatamount AS VatAmount,
        shp.new_totalamountaftervat AS FinalPrice,
        new_vatsettings.new_rate AS VatRate,
        new_timeslot.new_hours AS VisitHours,
        new_timeslot.new_timeslotId AS TimeSlotId,
        new_timeslot.new_name AS TimeSlotDisplayName,
        new_timeslot.new_shift AS VisitShift,
        PC.new_indv_parameter_condtionId AS NationalityId,
        bpc.new_name_ar AS NationalityNameAr,
        bpc.new_name AS NationalityNameEn,
        bpc.new_appname_appleview AS NationalityNameAr_appleview,
        bpc.new_appname_alt_appleview AS NationalityNameEn_appleview,
        new_hourlypromotion.new_code AS promotionCode,
        new_hourlypromotion.new_descriptionen AS DescriptionEn,
        new_hourlypromotion.new_descriptionar AS DescriptionAr

    FROM new_selectedhourlypricing AS shp
        CROSS APPLY OPENJSON(shp.new_condationparamter)
        WITH
        (
            value UNIQUEIDENTIFIER '$'
        ) AS chosen_paramter
        INNER JOIN new_indv_parameter_condtion PC
            ON chosen_paramter.value = PC.new_indv_parameter_condtionId
        INNER JOIN new_indv_baseparameter_condtion bpc
            ON pc.new_baseparameter_condtion = bpc.new_indv_baseparameter_condtionId
        JOIN new_timeslot
            ON shp.new_timeslot = new_timeslot.new_timeslotId
        FULL OUTER JOIN new_hourlypromotion
            ON shp.new_promotion = new_hourlypromotion.new_hourlypromotionId
        JOIN new_vatsettings
            ON shp.new_vatsetting = new_vatsettings.new_vatsettingsId
        JOIN new_rvservice s
            ON shp.new_service = s.new_rvserviceId
    WHERE shp.new_service IN (SELECT serviceId FROM @SelectedServiceIds)
          AND shp.new_timeslot IN
              (
                  SELECT [time].new_timeslotId
                  FROM new_timeslot [time]
                      INNER JOIN new_servicetimeslot servTime
                          ON [time].new_timeslotId = servTime.new_timeslot
                             AND servTime.new_service = shp.new_service
              )
          AND shp.statuscode = 1000
          AND shp.statecode = 1;
END;

GO
/****** Object:  StoredProcedure [dbo].[GetAllSelectedHourlyPricingDetails_AppleView]    Script Date: 9/8/2026 2:10:07 PM ******/
CREATE OR ALTER PROCEDURE [dbo].[GetAllSelectedHourlyPricingDetails_AppleView] @serviceId UNIQUEIDENTIFIER 
AS 
BEGIN 
    SET NOCOUNT ON; 
    
    if(@ServiceId is not null)
    BEGIN
        SELECT shp.new_selectedhourlypricingId AS SelectedHourlyPricingId, 
            shp.new_name AS DisplayNameEn, 
            shp.new_namear AS DisplayNameAr, 
            shp.new_name_appleview AS DisplayNameEn_appleview, 
            shp.new_namear_appleview AS DisplayNameAr_appleview, 
    
            shp.new_service AS ServiceId, 
    
            shp.new_resourcecount AS EmployeeNumber, 
            shp.new_weeklyvisits AS WeeklyVisits, 
            shp.new_occurrence AS ContractDuration, 
    
            shp.new_unitprice AS HourPrice, 
    
            shp.new_freereservationcount AS FreeReservationCount, 
            shp.new_no_visits as TotalVisits ,  
            shp.new_packageprice AS packagePriceAfterPromotion, 
            shp.new_promotionamount AS PromotionAmount, 
            shp.new_timeslot AS TimeslotId, 
            shp.new_recurrenceoption AS RecurrenceOptionId, 
            shp.new_pricelist AS PricingId, 
            shp.new_vatamount AS VatAmount, 
            shp.new_totalamountaftervat as FinalPrice, 
            new_vatsettings.new_rate AS VatRate, 
            new_timeslot.new_hours AS VisitHours, 
            new_timeslot.new_timeslotId AS TimeSlotId, 
            new_timeslot.new_name AS TimeSlotDisplayName, 
            new_timeslot.new_shift AS VisitShift, 
            PC.new_indv_parameter_condtionId AS NationalityId, 
            bpc.new_name_ar AS NationalityNameAr, 
            bpc.new_name AS NationalityNameEn, 
            bpc.new_appname_appleview AS NationalityNameAr_appleview, 
            bpc.new_appname_alt_appleview AS NationalityNameEn_appleview, 
            new_hourlypromotion.new_code AS promotionCode, --needed    
            new_hourlypromotion.new_descriptionen AS DescriptionEn, 
            new_hourlypromotion.new_descriptionar AS DescriptionAr 
    
        FROM new_selectedhourlypricing AS shp 
            CROSS APPLY 
            OPENJSON(shp.new_condationparamter) 
            WITH 
            ( 
                value UNIQUEIDENTIFIER '$' 
            ) AS chosen_paramter 
            INNER JOIN new_indv_parameter_condtion PC 
                ON chosen_paramter.value = PC.new_indv_parameter_condtionId 
            INNER JOIN new_indv_baseparameter_condtion bpc 
                ON pc.new_baseparameter_condtion = bpc.new_indv_baseparameter_condtionId 
            JOIN new_timeslot 
                ON shp.new_timeslot = new_timeslot.new_timeslotId 
            FULL OUTER JOIN new_hourlypromotion 
                ON shp.new_promotion = new_hourlypromotion.new_hourlypromotionId 
            JOIN new_vatsettings 
                ON shp.new_vatsetting = new_vatsettings.new_vatsettingsId 
        WHERE shp.new_service = @ServiceId 
            -- AND shp.new_timeslot IN 
            --     ( 
            --         SELECT [time].new_timeslotId 
            --         FROM new_timeslot [time] 
            --             INNER JOIN new_servicetimeslot servTime 
            --                 ON [time].new_timeslotId = servTime.new_timeslot 
            --                     AND servTime.new_service = @serviceId 
            --     ) 
        and shp.statuscode = 1000 
        and shp.statecode = 1 
    END
    ELSE
    BEGIN
        SELECT shp.new_selectedhourlypricingId AS SelectedHourlyPricingId, 
            shp.new_name AS DisplayNameEn, 
            shp.new_namear AS DisplayNameAr, 
            shp.new_name_appleview AS DisplayNameEn_appleview, 
            shp.new_namear_appleview AS DisplayNameAr_appleview, 
    
            shp.new_service AS ServiceId, 
    
            shp.new_resourcecount AS EmployeeNumber, 
            shp.new_weeklyvisits AS WeeklyVisits, 
            shp.new_occurrence AS ContractDuration, 
    
            shp.new_unitprice AS HourPrice, 
    
            shp.new_freereservationcount AS FreeReservationCount, 
            shp.new_no_visits as TotalVisits ,  
            shp.new_packageprice AS packagePriceAfterPromotion, 
            shp.new_promotionamount AS PromotionAmount, 
            shp.new_timeslot AS TimeslotId, 
            shp.new_recurrenceoption AS RecurrenceOptionId, 
            shp.new_pricelist AS PricingId, 
            shp.new_vatamount AS VatAmount, 
            shp.new_totalamountaftervat as FinalPrice, 
            new_vatsettings.new_rate AS VatRate, 
            new_timeslot.new_hours AS VisitHours, 
            new_timeslot.new_timeslotId AS TimeSlotId, 
            new_timeslot.new_name AS TimeSlotDisplayName, 
            new_timeslot.new_shift AS VisitShift, 
            PC.new_indv_parameter_condtionId AS NationalityId, 
            bpc.new_name_ar AS NationalityNameAr, 
            bpc.new_name AS NationalityNameEn, 
            bpc.new_appname_appleview AS NationalityNameAr_appleview, 
            bpc.new_appname_alt_appleview AS NationalityNameEn_appleview, 
            new_hourlypromotion.new_code AS promotionCode, --needed    
            new_hourlypromotion.new_descriptionen AS DescriptionEn, 
            new_hourlypromotion.new_descriptionar AS DescriptionAr 
    
        FROM new_selectedhourlypricing AS shp 
            CROSS APPLY 
            OPENJSON(shp.new_condationparamter) 
            WITH 
            ( 
                value UNIQUEIDENTIFIER '$' 
            ) AS chosen_paramter 
            INNER JOIN new_indv_parameter_condtion PC 
                ON chosen_paramter.value = PC.new_indv_parameter_condtionId 
            INNER JOIN new_indv_baseparameter_condtion bpc 
                ON pc.new_baseparameter_condtion = bpc.new_indv_baseparameter_condtionId 
            JOIN new_timeslot 
                ON shp.new_timeslot = new_timeslot.new_timeslotId 
            FULL OUTER JOIN new_hourlypromotion 
                ON shp.new_promotion = new_hourlypromotion.new_hourlypromotionId 
            JOIN new_vatsettings 
                ON shp.new_vatsetting = new_vatsettings.new_vatsettingsId 
        WHERE 
        -- shp.new_timeslot IN 
        --         ( 
        --             SELECT [time].new_timeslotId 
        --             FROM new_timeslot [time] 
        --                 INNER JOIN new_servicetimeslot servTime 
        --                     ON [time].new_timeslotId = servTime.new_timeslot 
        --                         AND servTime.new_service = shp.new_service 
        --         ) 
        -- and
         shp.statuscode = 1000 
        and shp.statecode = 1 
    END
END 




GO


