#使用Json格式的参数调用RESTFul的WebService
..\Global\Reference.ps1

	$body = @{
	    user_name = "accountTestData";
	    password = "1";
	    tenant_code = "mfel_test";
	    skip_duplicate_entries = $true;
	};
	$baseUrl = "http://58.215.183.198:8026";
	$loginUrl = "/saas-account-local/certification/center/login";
	$positionUrl = "http://58.215.183.198:8372/saas-user-sync-local/post/import";
	$contentType = "application/json";
	try
	{
		$response = Invoke-RestMethod -Uri ($baseUrl + $loginUrl) -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $body -Compress))) -ContentType $contentType;
		$ticketValue = $response.ticket;
		#上传岗位数据
		$body =  New-Object -TypeName System.Collections.ArrayList;
		$data = [Esap.Integrator.Tools.ExcelHelper]::GetDataFromExcel("D:\KanBox\Work\Documents\Projects\EHR TO E-LEARNING INTERFACE\马克华菲部门、人员、岗位数据(150123new!).xlsx","部门信息",$true);
		$data.Columns.Remove("部门简称");
	 	$data.Columns.Remove("助记符");
		$data.Columns.Remove("上级部门");
	 	$data.Columns.Remove("是否一级部门");	
		$data.Columns.Remove("负责人");
	 	$data.Columns.Remove("所属区域");			
		$data.Columns.Remove("区域编码");
	 	$data.Columns.Remove("部门简介");				
		$data.Columns["部门编码"].ColumnName = "code";
		$data.Columns["部门名称"].ColumnName = "name";
		$headers = @{};
		$headers.Add("ticket",$ticketValue);
		$response = Invoke-RestMethod -Uri $positionUrl -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes((($data | select $data.Columns.ColumnName) | ConvertTo-Json -Compress))) -ContentType $contentType -Headers $headers;
		$response;
	}
	catch 
	{ 
		$Error;
		$result = $_.Exception.Response.GetResponseStream();
        $reader = New-Object System.IO.StreamReader($result);
        $responseBody = $reader.ReadToEnd();
		$responseBody;
	}
