$Erroractionpreference = "Stop"
#来福士接口

#region 初始化

if ($args.Count -eq 1)
{
    cd $args[0];
}

..\Global\Reference.ps1
..\Global\Database.ps1
..\Global\Function.ps1
..\Global\Variable.ps1

$job_event_id = "I002";
$job_category = "集成"; #集成/数据/监控/备份/应用
$job_provider = "DRP"; #ERP/POS/VIP/CRM/HR/OA/BI/EFAST/EWMS/WMS
$job_task_category = "应用集成";
$job_task_name = "来福士日交易数据传输";

#endregion

$currentDateLOG = $(get-date).ToString("yyyy-MM-dd");
#错误日志
$ErrorTip = New-Object -TypeName System.Text.StringBuilder

function callService()
{
	param
	(
		[String]$mallName,		#地区商场名称
		[String]$serviceUri,    #WebService URL
		[String]$mallid,		#商场编号
		[String]$storeCode,		#店铺编号
		[String]$ItemCode,		#交易货号
		[String]$userName,		#用户名
		[String]$password,		#密码
		[String]$licensekey,	#许可证书
		[String]$khdm,			#客户代码
		[String]$clientUrl		#Client.Url
	)
	$currentDate = $(get-date).AddDays(-1).ToString("yyyy-MM-dd");
	$sql = "select a.RQ as rq,a.DJBH,a.DM1,a.SL as sl,a.JE as je from lsxhd a LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=a.DJBH WHERE a.dm1 in ($khdm) AND MARK_TRANSED.Status IS NULL
			union all
			select b.RQ as rq,b.DJBH,b.DM1,-b.SL as sl,-b.JE as je from lsthd b LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=b.DJBH WHERE b.dm1 in ($khdm) AND MARK_TRANSED.Status IS NULL";
			
	$masterData = [Esap.Integrator.Tools.DataBaseHelper]::FillDataTable($sql, 3600, $mark_erp_Con);
	$sql = "select b.DJBH as djbh,a.DM1 as dm1,b.MXBH as mxbh,b.SL as sl,b.JE as je from lsxhd a left join lsxhdmx b on a.djbh = b.djbh LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=b.DJBH where a.dm1 in ($khdm) and MARK_TRANSED.Status IS NULL
			union all
			select b.DJBH as djbh,a.DM1 as dm1,b.MXBH as mxbh,-b.SL as sl,-b.JE as je from lsthd a left join lsthdmx b on a.djbh = b.djbh LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=b.DJBH where a.dm1 in ($khdm) and MARK_TRANSED.Status IS NULL";
	$detailData = [Esap.Integrator.Tools.DataBaseHelper]::FillDataTable($sql, 3600, $mark_erp_Con);
	#汇总数据
	$sql= "select sum(xsl) as ssl,sum(xje) as sje,sum(tsl) as tsl,sum(tje) as tje from 
						(
					select sl as xsl,je as xje,0 tsl,0 tje from lsxhd LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=LSXHD.DJBH where dm1 in ($khdm) and MARK_TRANSED.Status IS NULL
					union all
					select 0 as xsl,0 as xje,sl as tsl,je as tje from lsthd LEFT JOIN MARK_TRANSED ON MARK_TRANSED.DJBH=LSTHD.DJBH where dm1 in ($khdm) and MARK_TRANSED.Status IS NULL
					) a"
	
	$summaryData = [Esap.Integrator.Tools.DataBaseHelper]::FillDataTable($sql, 3600, $mark_erp_Con);

	
	New-WebServiceProxy -Uri $serviceUri -Namespace "Raffles" | Out-Null;
	$client = New-Object -TypeName Raffles.sales;
	$client.Url = $clientUrl;
	if ($masterData -ne $null) 
  {
	foreach($masterRow in $masterData.Rows)
	{

		#POS请求
		$posRequest = New-Object -TypeName Raffles.postsalescreaterequest;
		#POS响应
		$posResponse = New-Object -TypeName Raffles.postsalescreateresponse;
		#POS请求头信息(许可证、用户名、密码)
		$posRequestHead = New-Object -TypeName Raffles.requestheader;
		#POS交易汇总信息(交易日期、交易时间、店铺号、商场号、流水号、货品数量、金额)
		$posMaster = New-Object -TypeName Raffles.saleshdr;
		#POS交易明细信息(货品编号、数量、金额)
		$posDetails = New-Object -TypeName System.Collections.ArrayList;
		#付款明细
		$posTenders = New-Object -TypeName System.Collections.ArrayList;
		#配送信息
		$posDelivery = New-Object -TypeName Raffles.salesdelivery;
		#付款项
		$posTender = New-Object -TypeName Raffles.salestender;
		$posTender.lineno = 1;										#
		$posTender.tendercode = "CH";
		$posTender.payamount = $masterRow["je"];
		$posTender.baseamount = $masterRow["je"];
		$posTenders.Add($posTender) | Out-Null;
		$posRequest.salestenders = $posTenders.ToArray();
		$posRequest.salesdlvy = $posDelivery;

		$posRequestHead.licensekey = $licensekey;					#许可证书
		$posRequestHead.username = $userName;						#用户名
		$posRequestHead.password = $password;						#密码
		$posRequestHead.messagetype = "SALESDATA";					#消息类型[SALESDATA]
		$posRequestHead.messageid = "332";							#消息ID[332]
		$posRequestHead.version = "V332M";							#版本编号[V332M]
		
		$posMaster.txdate_yyyymmdd = $masterRow["rq"].ToString("yyyyMMdd");		#交易日期
		$posMaster.txtime_hhmmss = "100000";									#交易时间
		$posMaster.mallid = $mallid;											#商场编号
		$posMaster.storecode = $storeCode;										#店铺编号
		$posMaster.tillid = "01";												#收银机号
		$posMaster.salestype = "SA";											#单据类型SA-销，SR-退
		$posMaster.txdocno = $masterRow["DJBH"];								#销售单号
		$posMaster.mallitemcode = $ItemCode;									#RMS货号
		$posMaster.cashier = "01";												#收银员编号
		$posMaster.netqty = $masterRow["sl"];									#净数量
		$posMaster.sellingamount = $masterRow["je"];							#销售金额
		$posMaster.netamount = $masterRow["je"];								#净金额
		$posMaster.paidamount = $masterRow["je"];								#付款金额
		$posMaster.issueby = "FairWhale";									#创建人
		$posMaster.issuedate_yyyymmdd = $masterRow["rq"].ToString("yyyyMMdd"); 		#创建日期
		$posMaster.issuetime_hhmmss = "100000";									#创建时间
				
		$i = 0
		foreach($detailRow in $detailData.Select("DJBH='" + $masterRow["DJBH"].ToString() + "'"))
		{
			$i=$i + 1
			$posDetail = New-Object -TypeName Raffles.salesitem;
			$posDetail.iscounteritemcode = "1";			
			$posDetail.lineno = $i;							#流水号
			$posDetail.storecode = $storeCode;				#店铺编号
			$posDetail.mallitemcode = $ItemCode;			#货号
			$posDetail.counteritemcode = $ItemCode;			#租户货号
			$posDetail.itemcode = $ItemCode;				#商品编号
			$posDetail.plucode = $ItemCode;					#商品内部编号
			$posDetail.qty = $detailRow["sl"];				#数量
			$posDetail.netamount = $detailRow["je"];		#金额
#			$posDetail.payamount = $detailRow["je"];		#付款金额
#			$posTender.tendercode = "CH";					#付款代码
			$posDetails.Add($posDetail) | Out-Null;
			
		}

		$posRequest.header = $posRequestHead;
		$posRequest.salestotal = $posMaster;
		$posRequest.salesitems = $posDetails.ToArray();
		$posResponse = $client.postsalescreate($posRequest);

		if ($posResponse.header.responsecode -eq 0)
		{"OK";}
		else
		{$posResponse.header.responsemessage + "(" + $posResponse.header.responsecode + ")";
		$ErrorTip.Append($posResponse.header.responsemessage + "(" + $posResponse.header.responsecode + ")").Append([System.Environment]::NewLine) | Out-Null
		}
	}
	#


	#POS汇总请求
	$posSummaryRequest = New-Object -TypeName Raffles.postdailysalessummaryrequest;
	#POS汇总响应
	$posSummaryResponse = New-Object -TypeName Raffles.postdailysalessummaryresponse;
	#POS汇总交易信息(交易日期、交易时间、店铺号、商场号、流水号、货品数量、金额)
	$posSummaryMaster = New-Object -TypeName Raffles.dailysalessummary;
	
	$posSummaryMaster.localstorecode = $storeCode; 											#本地店铺号
	$posSummaryMaster.txdate_yyyymmdd = $masterRow["rq"].ToString("yyyyMMdd");				#交易日期
	$posSummaryMaster.txtime_hhmmss = "100000";												#交易时间
	$posSummaryMaster.mallid = $mallid;														#商场编号
	$posSummaryMaster.storecode = $storeCode;												#店铺号
	$posSummaryMaster.tillid = "01";														#收银机号
	$posSummaryMaster.txdocno = $masterRow["DJBH"];											#销售单号
	$posSummaryMaster.ttlsalesqty = $summaryData.Rows[0]["ssl"];							#销售总数量
	$posSummaryMaster.ttlsalesamt = $summaryData.Rows[0]["sje"];							#销售总金额
	$posSummaryMaster.ttlrefundqty = $summaryData.Rows[0]["tsl"];							#退货总数量
	$posSummaryMaster.ttlrefundamt = $summaryData.Rows[0]["tje"];							#退货总金额
	$posSummaryMaster.ttldoccount = 0;														#总销售笔数
	$posSummaryMaster.cashier = 01;															#收银员编号
	$posSummaryMaster.issuedate_yyyymmdd = $masterRow["rq"].ToString("yyyyMMdd");			#创建日期
	            
    $posSummaryRequest.header = $posRequestHead;
    $posSummaryRequest.salessummary = $posSummaryMaster;
	
	$posSummaryResponse = $client.postdailysalessummary($posSummaryRequest);
	
	if ($posSummaryResponse.header.responsecode -eq 0)
	{
		#Set MARK_TRANSED
		foreach($masterRow in $masterData.Rows)
		{
			$m_djbh = $masterRow["DJBH"];
			$sql = "INSERT INTO MARK_TRANSED (DJBH,Status) VALUES ('$m_djbh',0)";
			[Esap.Integrator.Tools.DataBaseHelper]::ExecuteNonQuery($sql, $mark_erp_Con) | Out-Null;
		}
	"OK";
	}
	else
	{ $posSummaryResponse.header.responsemessage + "(" + $posSummaryResponse.header.responsecode + ")";
	 $ErrorTip.Append($posSummaryResponse.header.responsemessage + "(" + $posSummaryResponse.header.responsecode + ")").Append([System.Environment]::NewLine) | Out-Null
	}
  }
 	else 
	{
	$ErrorTip.Append($mallName).Append("没有交易数据！").Append([System.Environment]::NewLine) | Out-Null
	}
		
	if ( $ErrorTip.Length -gt 0 )
	{
		$job_end_date = [System.Datetime]::Now;
		$ErrorTip.ToString();
		g_WriteLog $job_event_id $job_category "警告" $job_provider $job_task_category $job_task_name "$ErrorTip.ToString()" $job_start_date $job_end_date "完成";
	}
	else
	{
		"Check OK!"
	}
}


try
{

    $job_start_date = [System.Datetime]::Now;
    $job_task_name + "开始：" + $job_start_date
	
    "Start 上海来福士:" + $(Get-Date)
    #上海来福士
    callService "上海来福士" "http://rcs-ws.capitaland.com.cn/post-sales/salesSoap?WSDL" "0001" "0507L1" "0507L1" "0507L1" "E1D58F821BCA4A7F9B1822432898F97E" "52DB52811C864B40AE3D99D87DFC7DEE" "'010105'" "http://rcs-ws.capitaland.com.cn/post-sales/salesSoap";


    "Start 成都来福士:" + $(Get-Date)
    #成都来福士
    callService "成都来福士" "http://rcws.capitaland.com.cn/sales.asmx?WSDL" "5012" "5012A00030" "5012A000301" "5012A00030" "5012A00030" "5012A0003001" "'223031','223032'" "http://rcws.capitaland.com.cn/sales.asmx";
    #callService "http://180.168.105.214:8080/TTPOS/sales.asmx?WSDL" "2037" "A00181" "A001811" "010201" "010201" " " "'010111','010102'";
    #http://rcws.capitaland.com.cn/sales.asmx?WSDL

    $job_end_date = [System.Datetime]::Now;
	$job_task_name + "结束：" + $job_end_date;
	g_WriteLog $job_event_id $job_category "信息" $job_provider $job_task_category $job_task_name "任务执行完成" $job_start_date $job_end_date "完成";
}
catch
{
	 $Error;
    #g_WriteLog $job_event_id $job_category "错误" $job_provider $job_task_category $job_task_name $Error $job_start_date $job_end_date "未处理";
     g_SendMail $System_Mail $MyInvocation.MyCommand.Name 编号$job_event_id-$Error;
}
finally
{
	$Error.Clear();
}
