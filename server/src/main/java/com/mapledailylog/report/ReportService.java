package com.mapledailylog.report;

import java.time.LocalDate;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class ReportService {

    public Map<String, Object> createDailyReport(String ocid, LocalDate reportDate) {
        return Map.of(
                "status", "planned",
                "ocid", ocid,
                "reportDate", reportDate.toString(),
                "rule", "Compare the previous last snapshot with the report date last snapshot."
        );
    }
}
