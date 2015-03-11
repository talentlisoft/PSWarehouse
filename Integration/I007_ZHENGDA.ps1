$_DEBUG = $false;

if ($_DEBUG -eq $true)
{
	$m_storeCode = '0101I6';
	$serviceUri = 'http://edi.superbrandmall.com:8010/sales.asmx';
	$m_MainSQL = "SELECT to_char(XF_TXDATE,'yyyymmdd') AS txdate, XF_TXTIME, XF_STORECODE, XF_TILLID, XF_TXTYPE, XF_DOCNO, 
	XF_CLIENTCODE, XF_CASHIER, XF_SALESMAN, XF_NETQTY,  XF_NETAMOUNT FROM XF_TRANSSALESTOTAL WHERE XF_PAIDAMOUNT <0 AND rownum = 1";
}
else
{
	$m_storeCode = '0101Q6';
	$serviceUri = 'http://edi.superbrandmall.com:8009/sales.asmx';
	$m_MainSQL = "SELECT to_char(XF_TRANSSALESTOTAL.XF_TXDATE,'yyyymmdd') AS txdate, XF_TRANSSALESTOTAL.XF_TXTIME, XF_TRANSSALESTOTAL.XF_STORECODE, XF_TRANSSALESTOTAL.XF_TILLID, XF_TRANSSALESTOTAL.XF_TXTYPE, 
	XF_TRANSSALESTOTAL.XF_DOCNO, XF_TRANSSALESTOTAL.XF_CLIENTCODE, XF_TRANSSALESTOTAL.XF_CASHIER, XF_TRANSSALESTOTAL.XF_SALESMAN, XF_TRANSSALESTOTAL.XF_NETQTY, 
	XF_TRANSSALESTOTAL.XF_NETAMOUNT FROM XF_TRANSSALESTOTAL  
	LEFT JOIN MARK_TRANSEDSALESTOTAL ON MARK_TRANSEDSALESTOTAL.XF_TXDATE = XF_TRANSSALESTOTAL.XF_TXDATE AND MARK_TRANSEDSALESTOTAL.XF_DOCNO = XF_TRANSSALESTOTAL.XF_DOCNO
	WHERE XF_TRANSSALESTOTAL.XF_STORECODE = '$m_storeCode' AND MARK_TRANSEDSALESTOTAL.TR_STATUS IS NULL";	
}

#include Global functions
..\Global\Reference.ps1
..\Global\Database.ps1
..\Global\Function.ps1
..\Global\Variable.ps1

$job_event_id = "I007";
$job_category = "集成"; #集成/数据/监控/备份/应用
$job_provider = "DRP"; #ERP/POS/VIP/CRM/HR/OA/BI/EFAST/EWMS/WMS
$job_task_category = "应用集成";
$job_task_name = "正大广场日交易数据传输";

#得到脚本的名称
$ls_AppName = [System.IO.path]::GetFilenameWithoutExtension($MyInvocation.MyCommand.Name);

#开始日志
Start-Transcript -Path ([String]::Concat(".\\log\\" +$ls_AppName+ "-" , $(get-date).ToString("yyyy-MM-dd") , ".txt")) -Append | Out-Null


$job_start_date = [System.Datetime]::Now;
$job_task_name + "开始：" + $job_start_date

#错误日志
$ErrorTip = New-Object -TypeName System.Text.StringBuilder
try
{
	New-WebServiceProxy -Uri $serviceUri -Namespace "SBM" | Out-Null;
	$client = New-Object -TypeName SBM.salestrans;
	$m_Pscr = New-Object -TypeName SBM.postsalescreaterequest; #PostsalescreateRequest:销售单请求


	$m_Header = New-Object -TypeName SBM.requestheader;
	$m_SalesTotal = New-Object -TypeName SBM.saleshdr;
	$m_SalesResponse = New-Object -TypeName SBM.postsalescreateresponse;
	$m_TotalDisCounts = New-Object -TypeName System.Collections.ArrayList;
	$m_ItemDisCounts = New-Object -TypeName System.Collections.ArrayList;
	$m_SalesItems = New-Object -TypeName System.Collections.ArrayList;
	$m_SalesPromotions =  New-Object -TypeName System.Collections.ArrayList;
	$m_SaelsItemTaxs =  New-Object -TypeName System.Collections.ArrayList;
	$m_SalesTenders =  New-Object -TypeName System.Collections.ArrayList;

	$masterData = [Esap.Integrator.Tools.DataBaseHelper]::FillDataTable($m_MainSQL, 3600, $POS_admin);

	if ($masterData -ne $null) 
	{
		foreach($masterRow in $masterData.Rows)
		{
			#Header标头信息
			#Reset all ArrayLists
			$m_SalesPromotions.Clear();
			$m_TotalDisCounts.Clear();
			$m_ItemDisCounts.Clear();
			$m_SalesItems.Clear();
			$m_SaelsItemTaxs.Clear();
			$m_SalesTenders.Clear();
			
			
			if ($_DEBUG -eq $true)
			{
				$salesDate = '20150127';
			}
			else
			{
				$salesDate = $masterRow["txdate"];
			}
			$m_Header.set_licensekey('');                                #许可证书	string
			$m_Header.set_username('120756');                            #用户名	string
			$m_Header.set_password('123456');                            #密码	string
			$m_Header.set_lang('lang');                                  #语言	string
			$m_Header.set_pagerecords(0);                                #每页记录数	integer
			$m_Header.set_pageno(0);                                     #页数	integer
			$m_Header.set_updatecount(0);                                #每次更新记录数	integer
			$m_Header.set_messagetype('SALESDATA');                      #消息类型	string	固定值：SALESDATA
			$m_Header.set_messageid('332');                              #消息ID	string	固定值：332
			$m_Header.set_version('V332M');                              #版本编号	string	固定值：V332M

			$m_Pscr.set_header($m_Header);
			#SalesTotal:销售单主表
			$m_SalesTotal.set_localstorecode('');                        #本地店铺号	string	保留
			$m_SalesTotal.set_reservedocno('');                          #销售预留库存单号	string	保留(最大长度:30)
			$m_SalesTotal.set_txdate_yyyymmdd($salesDate);               #交易日期	string	固定长度:8,固定格式：YYYYMMDD
			$m_SalesTotal.set_txtime_hhmmss($masterRow["XF_TXTIME"]);    #交易时间	string	固定长度:6,固定格式：HHMMSS
			$m_SalesTotal.set_mallid('01');                              #商场编号	string	最大长度:6商场提供固定值,由商场提供 可以填：01
			$m_SalesTotal.set_storecode('120756');                       #店铺号	string	最大长度:20 由商场提供,Web服务系统需要校验该店铺的有效性.可以填：120756
			$m_SalesTotal.set_tillid($masterRow["XF_TILLID"]);           #收银机号	string	可用01或者02表示,如果专柜只有一台收银机就用01表示，如果有两台则第二台用02表示，依次类推,Web服务系统需要校验该收银机编号的有效性,固定长度:2
			$m_SalesTotal.set_salestype('SA');                           #单据类型	string	SA:店内销售,SR:店内退货/取消交易,最大长度:2,销售总金额为正数时，销售类型为SA；销售总金额为负数时，销单类型为SR
			
			#销售唯一编号为 店铺号+日期+XF_DOCNO
			$m_SalesTotal.set_txdocno($m_storeCode+$salesDate+$masterRow["XF_DOCNO"]);           #销售单号	string	最大长度:30,商铺销售单号,Web服务系统如果判断到此单号的记录已经存在，返回错误信息
			$m_SalesTotal.set_orgtxdate_yyyymmdd('');                    #原交易日期	string	固定长度:8,固定格式：YYYYMMDD,退货时，原交易日期,如果是按单退货，提供此日期
			$m_SalesTotal.set_orgstorecode('120756');                    #原交易店铺号	string	最大长度:20,同店铺号码,退货时，原交易店铺号,如果是按单退货，提供此店铺号
			$m_SalesTotal.set_orgtillid($masterRow["XF_TILLID"]);        #原收银机号	string	固定长度:2,退货时，原收银机号,如果是按单退货，提供此收银机号
			$m_SalesTotal.set_orgtxdocno('');                            #原销售单号	string	最大长度:30,原销售单号,如果提供了【原销售单号】，Web服务系统判断此单号【是否存在】或者【是否已经退货】，如果【不存在】或者【已退货】，Web服务系统返回错误信息
			$m_SalesTotal.set_mallitemcode('101887');                    #货号	string	最大长度:30,由商场提供 可以填：1207561,Web服务系统校验货号是否有效
			$m_SalesTotal.set_cashier('666666');                         #收银员编号	string	否	最大长度:10,固定值666666
			$m_SalesTotal.set_vipcode('');                               #VIP卡号	string	保留
			$m_SalesTotal.set_salesman('');                              #销售员	string	保留
			$m_SalesTotal.set_demographiccode('');                       #顾客统计代码	string	保留
			$m_SalesTotal.set_demographicdata('');                       #顾客统计值	string	保留
			$m_SalesTotal.set_netqty($masterRow["XF_NETQTY"]);           #净数量	decimal { 4 }	销售总数量
			$m_SalesTotal.set_originalamount($masterRow["XF_NETAMOUNT"]);  #原始金额	decimal { 4 }	默认赋0值
			$m_SalesTotal.set_sellingamount($masterRow["XF_NETAMOUNT"]);    #销售金额	decimal { 4 }	销售金额
			$m_SalesTotal.set_couponnumber('');                          #优惠券号码	string	保留
			$m_SalesTotal.set_coupongroup('');                           #优惠券组	string	保留
			$m_SalesTotal.set_coupontype('');                            #优惠券类型	string	保留
			$m_SalesTotal.set_couponqty(0);                              #优惠券数量	integer	保留

			#Begin of TotalDiscount
			$m_SalesDiscount1 = New-Object -TypeName SBM.salesdiscount;
			$m_SalesDiscount2 = New-Object -TypeName SBM.salesdiscount;
			$m_SalesDiscount1.set_discountapprove('');                   #折扣允许	string	保留
			$m_SalesDiscount1.set_discountmode('0');                     #折扣模式	string	0：代表没有折扣,1：代表折扣百分比,2：代表折扣金额
			$m_SalesDiscount1.set_discountvalue(0);                      #折扣额	decimal { 4 }	默认赋0值,可能是百分比或折扣金额
			$m_SalesDiscount1.set_discountless(0);                       #折扣差额	decimal { 4 }	默认赋0值,具体折扣金额
			$m_SalesDiscount2 = $m_SalesDiscount1;
			$m_TotalDisCounts.Add($m_SalesDiscount1) | Out-Null;
			$m_TotalDisCounts.Add($m_SalesDiscount2) | Out-Null;
			$m_SalesTotal.set_totaldiscount($m_TotalDisCounts.ToArray());
			#End of TotalDiscount

			$m_SalesTotal.set_ttltaxamount1(0);                          #总税额1	decimal { 4 }	保留
			$m_SalesTotal.set_ttltaxamount2(0);                          #总税额2	decimal { 4 }	保留
			$m_SalesTotal.set_netamount($masterRow["XF_NETAMOUNT"]);     #净金额	decimal { 4 }	销售净金额
			$m_SalesTotal.set_paidamount($masterRow["XF_NETAMOUNT"]);    #付款金额	decimal { 4 }	
			$m_SalesTotal.set_changeamount(0)                            #找零金额	decimal { 4 }	保留,默认赋0值
			$m_SalesTotal.set_priceincludetax('');                       #售价是否含税	string	保留
			$m_SalesTotal.set_shoptaxgroup('');                          #店铺税组	string	保留
			$m_SalesTotal.set_extendparam('');                           #扩展参数	string	保留
			$m_SalesTotal.set_invoicetitle('');                          #发票抬头	string	保留
			$m_SalesTotal.set_invoicecontent('');                        #发票内容	string	保留
			$m_SalesTotal.set_issueby('666666');                         #创建人	string	最大长度:10,默认为666666

			$m_SalesTotal.set_issuedate_yyyymmdd([System.Datetime]::Now.ToString('YYYYmmdd'));            #创建日期	string	固定长度:8
			$m_SalesTotal.set_issuetime_hhmmss([System.Datetime]::Now.ToString('HHMMSS'));                  #创建时间	string	固定长度:6
			$m_SalesTotal.set_ecorderno('');                             #网购订单号	string	保留
			$m_SalesTotal.set_buyerremark('');                           #卖家备注	string	保留
			$m_SalesTotal.set_orderremark('');                           #交易备注	string	保留
			$m_SalesTotal.set_status('20');                              #状态	string	保留,10:新增/ 20:付款/30:付款取消/40:订单取消,在【销售单查询】中用于显示

			$m_Pscr.set_salestotal($m_SalesTotal);

			#Begin of SalesItems 循环
			$m_SalesItem = New-Object -TypeName SBM.salesitem;
			$m_SalesItem.set_iscounteritemcode('1');                     #是否专柜货号	string	默认为1,固定长度:1
			$m_SalesItem.set_lineno(1);                                  #行号	long	一张销售单中存在多货号交易情况下，依次类推记录
			$m_SalesItem.set_storecode('120756');                        #店铺号	string	否	最大长度:20,由商场提供,Web服务系统需要校验该店铺的有效性
			$m_SalesItem.set_mallitemcode('101887')                      #货号	string	否	最大长度:30,由商场提供，同货号
			$m_SalesItem.set_counteritemcode('101887')                   #铺位货号	string	最大长度:30,由商场提供，同货号
			$m_SalesItem.set_itemcode('101887');                         #商品编号	string	否	最大长度:30,由商场提供，同货号
			$m_SalesItem.set_plucode('101887');                          #商品内部编号	string	否	最大长度:30,由商场提供，同货号
			$m_SalesItem.set_colorcode('');                              #商品颜色	string	保留
			$m_SalesItem.set_sizecode('');                               #商品尺码	string	保留
			$m_SalesItem.set_itemlotnum('');                             #商品批次	string	保留
			$m_SalesItem.set_serialnum('');                              #序列号	integer	保留
			$m_SalesItem.set_isdeposit('');                              #是否定金单	string	保留
			$m_SalesItem.set_iswholesale('');                            #是否批发	string	保留
			$m_SalesItem.set_invttype(1);                                #库存类型	integer	0:坏货退回/1:好货退回,默认为1,主要用于店内退货，在PDA店内退货时选择库存类型，单品后台系统根据库存类型进行控制是否增加库存
			$m_SalesItem.set_qty($masterRow["XF_NETQTY"]);               #数量	decimal { 4 }	销售数量
			$m_SalesItem.set_exstk2sales(1);                             #库存销售比例	decimal { 4 }	默认赋1值
			$m_SalesItem.set_originalprice($masterRow["XF_NETAMOUNT"]);  #原始售价	decimal { 4 }	默认赋0值
			$m_SalesItem.set_sellingprice($masterRow["XF_NETAMOUNT"]);   #售价	decimal { 4 }	默认赋0值
			$m_SalesItem.set_pricemode('');                              #价格模式	string	保留
			$m_SalesItem.set_priceapprove('');                           #允许改价	string	保留
			$m_SalesItem.set_couponnumber('');                           #优惠劵号码	string	保留
			$m_SalesItem.set_coupongroup('');                            #优惠劵组	string	保留
			$m_SalesItem.set_coupontype('');                             #优惠劵类型	string	保留
			# Begin of itemdiscount
			$m_ItemDisCounts.Add($m_SalesDiscount1) | Out-Null;
			$m_SalesItem.set_itemdiscount($m_ItemDisCounts.ToArray());
			# End itemdiscount
			$m_SalesItem.set_vipdiscountpercent(0);                      #VIP折扣率	decimal { 4 }	默认赋0值
			$m_SalesItem.set_vipdiscountless(0);                         #VIP折扣差额	decimal { 4 }	默认赋0值
			#Begin of salespromotion
			$m_SalesPromotion = New-Object -TypeName SBM.salespromtion;
			$m_SalesPromotions.Add($m_SalesPromotion) | Out-Null;
			$m_SalesItem.set_promotion($m_SalesPromotions.ToArray());    #商品促销信息	salespromtion	保留
			#End of salespromotion
			$m_SalesItem.set_totaldiscountless1(0);                      #整单折扣差额1	decimal { 4 }	默认赋0值
			$m_SalesItem.set_totaldiscountless2(0);                      #整单折扣差额2	decimal { 4 }	默认赋0值
			$m_SalesItem.set_totaldiscountless(0);                       #整单折扣差额	decimal { 4 }	默认赋0值
			$m_SalesItem.set_tax($m_SaelsItemTaxs.ToArray());
			$m_SalesItem.set_netamount($masterRow["XF_NETAMOUNT"]);      #净金额	decimal { 4 }	此货品销售金额
			$m_SalesItem.set_bonusearn(0);                               #获得积分	decimal { 4 }	默认赋0值
			$m_SalesItem.set_salesitemremark('');                        #交易明细备注	string	保留
			$m_SalesItem.set_refundreasoncode('');                       #退货原因	string	保留
			$m_SalesItem.set_extendparam('');                            #扩展参数	string	保留

			$m_SalesItems.Add($m_SalesItem) | Out-Null;
			#End of SalesItems
			$m_Pscr.set_salesitems($m_SalesItems.ToArray());
			
			if ($_DEBUG -eq $true)
			{
				$m_storeCode = $masterRow["XF_STORECODE"];
				$salesDate = $masterRow["txdate"];
			}
			
			$m_TenderSQL =	"SELECT (CASE WHEN xf_tendercode='10' THEN 'CH' ELSE 'OT' END) AS PAYCODE, 
			SUM(XF_PAYAMOUNT) AS TOTALPAYAMOUNT, SUM(XF_EXCESSMONEY) AS TOTALEXCESSMONEY 
			FROM XF_TRANSSALESTENDER WHERE XF_STORECODE = '$m_storeCode' AND XF_TXDATE = TO_DATE('$salesDate','YYYYMMDD') AND XF_DOCNO = '" + $masterRow['XF_DOCNO'] + "'" +
			" GROUP BY (CASE WHEN xf_tendercode='10' THEN 'CH' ELSE 'OT' END)";
			$tenderData = [Esap.Integrator.Tools.DataBaseHelper]::FillDataTable($m_TenderSQL, 3600, $POS_admin);
			if ($tenderData -ne $null)
			{
				$m_tendercount = 1;
				foreach($tenderRow in $tenderData.Rows)#Begin of SalesTender:循环
				{
					$m_SalesTender = New-Object -TypeName SBM.salestender;
					$m_SalesTender.set_lineno($m_tendercount);                  #行号	long	一张销售单中若出现多种支付方式依次类推产生
					$m_SalesTender.set_tendercode($tenderRow["PAYCODE"]);       #付款代码	string	固定长度:2,CH----现金,CI----国内银行卡,CO----国外银行卡,OT-----其他付款方式。接口数据应在TenderCode付款方式中填写对应方式付款实际金额，无对应付款方式时在其他付款方式字段填写剩余付款方式金额的合计；Web服务系统需要校验付款方式编号有效性
					$m_SalesTender.set_tendertype(0);                           #付款类型	integer	保留
					$m_SalesTender.set_tendercategory(0);                       #付款种类	integer	默认赋0值
					$m_SalesTender.set_payamount($tenderRow["TOTALPAYAMOUNT"]); #付款金额	decimal { 4 }	此付款方式的支付金额
					$m_SalesTender.set_baseamount($tenderRow["TOTALPAYAMOUNT"]);#本位币金额	decimal { 4 }	同payamount
					$m_SalesTender.set_excessamount($tenderRow["TOTALEXCESSMONEY"]);        #超额金额	decimal { 4 }	默认赋0值
					$m_SalesTender.set_extendparam('');                         #扩展参数	string	保留
					$m_SalesTender.set_remark('');                              #备注	string	保留
					$m_SalesTenders.Add($m_SalesTender) | Out-Null;
					$m_tendercount = $m_tendercount + 1;
				}
			}#End of SalesTender;
			$m_Pscr.set_salestenders($m_SalesTenders.ToArray());

			$m_SalesResponse = $client.postsalescreate($m_Pscr);
			
			if ($m_SalesResponse.header.responsecode -eq 0)
			{
				if ($_DEBUG -eq $false)#成功发送记录，标记数据库
				{
					$salesDocNo = $masterRow["XF_DOCNO"];
					$sql = "INSERT INTO MARK_TRANSEDSALESTOTAL (XF_TXDATE,XF_DOCNO) VALUES (TO_DATE($salesDate,'YYYYMMDD'),'$salesDocNo')";
    				[Esap.Integrator.Tools.DataBaseHelper]::ExecuteNonQuery($sql, $POS_admin) | Out-Null;
				}
			}
			else
			{
				$m_SalesResponse.header.responsemessage + "(" + $m_SalesResponse.header.responsecode + ")";
				$ErrorTip.Append($m_SalesResponse.header.responsemessage + "(" + $m_SalesResponse.header.responsecode + ")").Append([System.Environment]::NewLine) | Out-Null
			}
		}
		
	}
	else
	{
		#没有任何数据
		$ErrorTip.Append($mallName).Append("没有交易数据！").Append([System.Environment]::NewLine) | Out-Null
	}
	
	if ( $ErrorTip.Length -gt 0 )
	{
		$job_end_date = [System.Datetime]::Now;
		$ErrorTip.ToString();
		g_WriteLog $job_event_id $job_category "警告" $job_provider $job_task_category $job_task_name "$ErrorTip" $job_start_date $job_end_date "完成";
	}
	else
	{
		"Check OK!"
	}
}

catch
{
	 $Error;
    #g_WriteLog $job_event_id $job_category "错误" $job_provider $job_task_category $job_task_name $Error $job_start_date $job_end_date "未处理";
    g_SendMail $System_Mail $MyInvocation.MyCommand.Name 编号$job_event_id-$Error;
}

finally
{
	Stop-Transcript | Out-Null
	$Error.Clear();
}
