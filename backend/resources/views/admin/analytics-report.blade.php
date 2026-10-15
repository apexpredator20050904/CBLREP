{{--
    CBLREP municipal analytics report.

    Rendered to PDF by dompdf, which supports only a subset of CSS — no flexbox,
    no grid, no custom properties. Layout here is table-based and the styling is
    inline for that reason. Keep it that way when editing.
--}}
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>CBLREP Analytics Report — Trinidad, Bohol</title>
    <style>
        @page { margin: 28px 32px; }

        /* Core PDF fonts (Helvetica) are used deliberately: they need no
           embedded font program, which keeps the report around 10 KB instead
           of ~880 KB, and their WinAnsiEncoding still covers the accented
           barangay names such as "Sto. Niño". */
        body {
            font-family: Helvetica, Arial, sans-serif;
            font-size: 10.5px;
            color: #1c1917;
            margin: 0;
        }

        table { width: 100%; border-collapse: collapse; }

        .banner td { background-color: #1B382B; color: #ffffff; padding: 16px 18px; }
        .banner .title { font-size: 15px; font-weight: bold; letter-spacing: 1px; }
        .banner .sub { font-size: 9px; color: #cfe3d4; }

        h2 {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.6px;
            color: #2E5339;
            border-bottom: 1.5px solid #2E5339;
            padding-bottom: 4px;
            margin: 20px 0 8px;
        }

        .metrics td { border: 1px solid #e7e5e4; padding: 8px 10px; width: 33.33%; vertical-align: top; }
        .metrics .value { font-size: 19px; font-weight: bold; color: #2E5339; }
        .metrics .label { font-size: 8.5px; color: #57534e; }

        .grid td { padding: 0; vertical-align: top; width: 50%; }
        .grid td.inner { padding: 0 7px; }

        .data th {
            background-color: #f5f5f4;
            border-bottom: 1.5px solid #2E5339;
            padding: 6px 8px;
            text-align: left;
            font-size: 8.5px;
            text-transform: uppercase;
            letter-spacing: 0.4px;
            color: #44403c;
        }

        .data td { border-bottom: 1px solid #e7e5e4; padding: 5px 8px; font-size: 9.5px; }
        .data td.num { text-align: right; width: 60px; }
        .data tr.total td { font-weight: bold; border-top: 1.5px solid #2E5339; }

        .meta td { padding: 2px 0; font-size: 9px; color: #57534e; }
        .meta .key { width: 78px; font-weight: bold; color: #1c1917; }
    </style>
</head>
<body>

    <table class="banner">
        <tr>
            <td>
                <div class="title">CBLREP ANALYTICS REPORT</div>
                <div class="sub">Community-Based Local Resources Exchange Portal &middot; Municipality of Trinidad, Bohol</div>
            </td>
        </tr>
    </table>

    <table class="meta">
        <tr>
            <td class="key">Reporting period</td>
            <td>{{ $period['from'] }} to {{ $period['to'] }}</td>
        </tr>
        <tr>
            <td class="key">Generated</td>
            <td>{{ $generatedAt }}</td>
        </tr>
    </table>

    <h2>Community Overview</h2>
    <table class="metrics">
        <tr>
            @foreach (array_slice($summary, 0, 3) as $metric)
                <td>
                    <div class="value">{{ number_format($metric['value']) }}</div>
                    <div class="label">{{ $metric['label'] }}</div>
                </td>
            @endforeach
        </tr>
        <tr>
            @foreach (array_slice($summary, 3, 3) as $metric)
                <td>
                    <div class="value">{{ number_format($metric['value']) }}</div>
                    <div class="label">{{ $metric['label'] }}</div>
                </td>
            @endforeach
        </tr>
    </table>

    <table class="grid">
        <tr>
            <td class="inner">
                <h2>Exchanges by Type</h2>
                <table class="data">
                    <thead>
                        <tr>
                            <th>Type</th>
                            <th class="num">Count</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($exchanges as $row)
                            <tr>
                                <td>{{ $row['label'] }}</td>
                                <td class="num">{{ number_format($row['value']) }}</td>
                            </tr>
                        @endforeach
                        <tr class="total">
                            <td>Total recorded</td>
                            <td class="num">{{ number_format(array_sum(array_column($exchanges, 'value'))) }}</td>
                        </tr>
                    </tbody>
                </table>
            </td>
            <td class="inner">
                <h2>Barangay Coverage</h2>
                <table class="data">
                    <thead>
                        <tr>
                            <th>Barangay</th>
                            <th class="num">Verified</th>
                            <th class="num">Students</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($byBarangay as $row)
                            <tr>
                                <td>{{ $row['barangay'] }}</td>
                                <td class="num">{{ number_format($row['verified']) }}</td>
                                <td class="num">{{ number_format($row['students']) }}</td>
                            </tr>
                        @endforeach
                        <tr class="total">
                            <td>Total</td>
                            <td class="num">{{ number_format(array_sum(array_column($byBarangay, 'verified'))) }}</td>
                            <td class="num">{{ number_format(array_sum(array_column($byBarangay, 'students'))) }}</td>
                        </tr>
                    </tbody>
                </table>
            </td>
        </tr>
    </table>

    <table class="meta">
        <tr>
            <td class="key">Prepared for</td>
            <td>CBLREP Municipal Administration, Trinidad, Bohol</td>
        </tr>
        <tr>
            <td class="key">Note</td>
            <td>Figures reflect registered community members and are released under the municipality&rsquo;s data-privacy policy.</td>
        </tr>
    </table>

</body>
</html>
