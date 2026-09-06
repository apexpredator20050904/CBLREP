<?php
    $consoleIndexPath = public_path('admin/index.html');
    $consoleHtml = is_file($consoleIndexPath) ? file_get_contents($consoleIndexPath) : null;
?>

<?php if($consoleHtml): ?>
    
    <?php echo $consoleHtml; ?>

<?php else: ?>
    <!doctype html>
    <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>CBLREP · System Administrator Console</title>
            <style>
                body { font-family: system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif; background: #f3f4f6; color: #111827; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
                .card { max-width: 580px; margin: 24px 16px; padding: 32px; background: #fff; border-radius: 12px; box-shadow: 0 10px 30px rgba(0, 0, 0, .08); }
                h1 { font-size: 20px; margin: 0 0 10px; }
                p { margin: 0 0 12px; color: #4b5563; }
                code { background: #eef2f7; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
            </style>
        </head>
        <body>
            <div class="card">
                <h1>System Administrator Console — build required</h1>
                <p>The Admin Console SPA has not been deployed into this backend yet.</p>
                <p>From the admin console project (React/Vite), run:</p>
                <p><code>npm install &nbsp;&amp;&amp;&nbsp; npm run build</code></p>
                <p>This publishes the console into <code>public/admin</code>, and this page will then load it automatically.</p>
                <p>The Flutter mobile app and every JSON endpoint under <code>/api</code> are unaffected and fully operational.</p>
            </div>
        </body>
    </html>
<?php endif; ?>
<?php /**PATH C:\xampp\htdocs\community-based-portal\resources\views/admin-console.blade.php ENDPATH**/ ?>