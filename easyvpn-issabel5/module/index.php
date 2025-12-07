<?php
/* Módulo EasyVPN para Issabel 5 */

#include core Issabel helpers
include_once "libs/paloSantoGrid.class.php";
include_once "libs/paloSantoForm.class.php";
include_once "libs/paloSantoConfig.class.php";
include_once "libs/paloACL.class.php";
require_once "libs/misc.lib.php";

function _moduleContent(&$smarty, $module_name)
{
    global $arrConf;

    $base_dir = dirname($_SERVER['SCRIPT_FILENAME']);

    // Config del módulo (opcional)
    $module_conf = "$base_dir/modules/$module_name/configs/default.conf.php";
    if (file_exists($module_conf)) {
        include_once $module_conf;
        if (isset($arrConfModule) && is_array($arrConfModule)) {
            $arrConf = array_merge($arrConf, $arrConfModule);
        }
    }

    // Funciones del módulo
    include_once "modules/$module_name/libs/easyvpn.php";

    // Idioma
    load_language_module($module_name);

    // ACL
    if (!isset($arrConf['issabel_dsn']['acl'])) {
        return "ERROR: DSN de ACL no definido en configuración.";
    }

    $pDBACL = new paloDB($arrConf['issabel_dsn']['acl']);
    if (!empty($pDBACL->errMsg)) {
        return "ERROR DE DB (ACL): ".$pDBACL->errMsg;
    }

    $pACL = new paloACL($pDBACL);
    if (!empty($pACL->errMsg)) {
        return "ERROR DE ACL: ".$pACL->errMsg;
    }

    $user = isset($_SESSION['issabel_user']) ? $_SESSION['issabel_user'] : '';
    if ($user == '' || !$pACL->hasModulePrivilege($user, $module_name, 'access')) {
        return _tr('Access denied');
    }

    // --- Manejo de descargas antes de generar HTML ---
    $download = getParameter('download'); // 'ovpn' o 'tar'
    $cn       = getParameter('cn');

    if ($download && $cn) {
        $files = easyvpn_get_client_files($cn);
        $filePath = null;
        $fileName = null;

        if ($download === 'ovpn' && $files['ovpn']) {
            $filePath = $files['ovpn'];
        } elseif ($download === 'tar' && $files['tar']) {
            $filePath = $files['tar'];
        }

        if ($filePath && file_exists($filePath)) {
            $fileName = basename($filePath);
            header('Content-Type: application/octet-stream');
            header('Content-Disposition: attachment; filename="'.$fileName.'"');
            header('Content-Length: '.filesize($filePath));
            readfile($filePath);
            exit;
        } else {
            // Si algo falla, mostramos luego un mensaje en el HTML
            $smarty->assign("mb_message", _tr("No se encontró el archivo para descargar."));
        }
    }

    // --- Crear cliente desde el formulario ---
    $message = '';
    $messageClass = '';


    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $action = getParameter('action');

        if ($action === 'create_client') {
            $clientName = trim(getParameter('client_name'));
            $err = '';

            if (easyvpn_create_client($clientName, $err)) {
                $message      = _tr("Cliente VPN creado correctamente").": ".htmlspecialchars($clientName);
                $messageClass = "easyvpn-message-ok";
            } else {
                $message      = $err;
                $messageClass = "easyvpn-message-error";
            }

        } elseif ($action === 'revoke_client') {
            $cn = trim(getParameter('cn'));
            $err = '';

            if (easyvpn_revoke_client($cn, $err)) {
                $message      = _tr("Cliente VPN revocado correctamente").": ".htmlspecialchars($cn);
                $messageClass = "easyvpn-message-ok";
            } else {
                $message      = $err;
                $messageClass = "easyvpn-message-error";
            }
        } elseif ($action === 'regenerate_profile') {
             $cn = trim(getParameter('cn'));
             $err = '';

             if (easyvpn_regenerate_profile($cn, $err)) {
                $message      = "Perfil regenerado correctamente: ".htmlspecialchars($cn);
                $messageClass = "easyvpn-message-ok";
              } else {
                  $message      = $err;
                  $messageClass = "easyvpn-message-error";
              }
        } elseif ($action === 'service_control') {
            $op  = getParameter('op');
            $err = '';

            if (easyvpn_control_service($op, $err)) {
                $message      = "Servicio EasyVPN: operación '".htmlspecialchars($op)."' ejecutada correctamente.";
                $messageClass = "easyvpn-message-ok";
            } else {
                $message      = nl2br(htmlspecialchars($err));
                $messageClass = "easyvpn-message-error";
            }
        }
    }

    // Datos
    $clients = easyvpn_list_clients();
    $vpnServiceStatus = easyvpn_get_service_status();
    $status = easyvpn_get_status();

    // HTML
    $html  = '<link rel="stylesheet" type="text/css" href="modules/'.$module_name.'/css/style.css">';
    $html .= '<div class="easyvpn-container">';
    $html .= '  <div class="easyvpn-title">EasyVPN</div>';

    if ($message !== '') {
        $html .= '  <div class="easyvpn-message '.htmlspecialchars($messageClass).'">';
        $html .=        nl2br(htmlspecialchars($message));
        $html .= '  </div>';
    }

    // Barra de control del servicio
    $label = '';
    $colorClass = '';

    switch ($vpnServiceStatus) {
        case 'active':
            $label = 'Activo';
            $colorClass = 'easyvpn-service-active';
            break;
        case 'inactive':
            $label = 'Detenido';
            $colorClass = 'easyvpn-service-inactive';
            break;
        case 'failed':
            $label = 'Error';
            $colorClass = 'easyvpn-service-failed';
            break;
        default:
            $label = 'Desconocido';
            $colorClass = 'easyvpn-service-unknown';
            break;
    }

    $html .= '  <div class="easyvpn-service-bar">';
    $html .= '    <span class="easyvpn-service-label '.$colorClass.'">Estado servicio: '.htmlspecialchars($label).'</span>';

    $html .= '    <form method="post" style="display:inline;margin-left:10px;">';
    $html .= '      <input type="hidden" name="action" value="service_control">';
    $html .= '      <input type="hidden" name="op" value="start">';
    $html .= '      <input type="submit" value="Encender">';
    $html .= '    </form>';

    $html .= '    <form method="post" style="display:inline;margin-left:5px;">';
    $html .= '      <input type="hidden" name="action" value="service_control">';
    $html .= '      <input type="hidden" name="op" value="stop">';
    $html .= '      <input type="submit" value="Apagar">';
    $html .= '    </form>';

    $html .= '    <form method="post" style="display:inline;margin-left:5px;">';
    $html .= '      <input type="hidden" name="action" value="service_control">';
    $html .= '      <input type="hidden" name="op" value="restart">';
    $html .= '      <input type="submit" value="Reiniciar">';
    $html .= '    </form>';

    $html .= '  </div>';

    // Formulario crear cliente
    $html .= '  <div class="easyvpn-section-title">'._tr("Crear nuevo cliente").'</div>';
    $html .= '  <form method="post" class="easyvpn-form-inline">';
    $html .= '    <input type="hidden" name="action" value="create_client">';
    $html .= '    <label>'._tr("Nombre cliente (CN)").':</label> ';
    $html .= '    <input type="text" name="client_name" required> ';
    $html .= '    <input type="submit" value="'._tr("Crear").'">';
    $html .= '  </form>';

    // Tabla clientes
    $html .= '  <div class="easyvpn-section-title">'._tr("Clientes existentes (certificados)").'</div>';
    $html .= '  <table class="easyvpn-table">';
    $html .= '    <tr><th>CN</th><th>'._tr("Estado").'</th><th>'._tr("Acciones").'</th><th>'._tr("Descargas").'</th></tr>';

    if (empty($clients)) {
        $html .= '    <tr><td colspan="4">'._tr("No hay clientes aún.").'</td></tr>';
    } else {
        foreach ($clients as $c) {
            $cn    = $c['cn'];
            $stat  = ($c['status'] === 'V') ? _tr('Válido') : _tr('Revocado');
            $files = easyvpn_get_client_files($cn);

            // Links de descarga .ovpn y .tar
            $linkOvpn = $files['ovpn']
                ? '<a href="index.php?menu='.$module_name.'&download=ovpn&cn='.urlencode($cn).'">.ovpn</a>'
                : '-';

            $linkTar = $files['tar']
                ? '<a href="index.php?menu='.$module_name.'&download=tar&cn='.urlencode($cn).'">.tar</a>'
                : '-';

            // Botón Revocar solo si está válido
            if ($c['status'] === 'V') {
                $revokeForm = '
                    <form method="post" style="display:inline;" onsubmit="return confirm(\'¿Seguro que deseas revocar '.htmlspecialchars($cn, ENT_QUOTES, 'UTF-8').'\');">
                        <input type="hidden" name="action" value="revoke_client">
                        <input type="hidden" name="cn" value="'.htmlspecialchars($cn).'">
                        <input type="submit" value="'._tr('Revocar').'">
                    </form>';
            } else {
                $revokeForm = '<span style="color:#888;">'._tr('Revocado').'</span>';
            }

            // Botón REGENERAR PERFIL (siempre permitido, incluso si está revocado)
            $regenForm = '
                <form method="post" style="display:inline; margin-left:4px;">
                    <input type="hidden" name="action" value="regenerate_profile">
                    <input type="hidden" name="cn" value="'.htmlspecialchars($cn).'">
                    <input type="submit" value="Regenerar">
                </form>';

            // Construir fila
            $html .= '<tr>';
            $html .= '  <td>'.htmlspecialchars($cn).'</td>';
            $html .= '  <td>'.$stat.'</td>';
            $html .= '  <td>'.$revokeForm.' | '.$regenForm.'</td>';
            $html .= '  <td>'.$linkOvpn.' | '.$linkTar.'</td>';
            $html .= '</tr>';
        }
    }

    $html .= '  </table>';

    // Tabla conectados
    $html .= '  <div class="easyvpn-section-title">'._tr("Clientes conectados").'</div>';
    $html .= '  <div class="easyvpn-status-header">';
    $html .= '    <span id="easyvpn-status-indicator">Actualizado</span>';
    $html .= '  </div>';

    $html .= '  <table id="easyvpn-status-table" class="easyvpn-table">';
    $html .= '    <tr><th>CN</th><th>Real Address</th><th>IP VPN</th><th>Bytes Recv</th><th>Bytes Sent</th><th>Conectado Desde</th></tr>';

    if (empty($status)) {
        $html .= '    <tr><td colspan="6">'._tr("No hay clientes conectados o no hay status.").'</td></tr>';
    } else {
        foreach ($status as $s) {
            $html .= '    <tr>';
            $html .= '      <td>'.htmlspecialchars($s['cn']).'</td>';
            $html .= '      <td>'.htmlspecialchars($s['real_address']).'</td>';
            $html .= '      <td>'.htmlspecialchars($s['virtual_address']).'</td>';
            $html .= '      <td>'.htmlspecialchars($s['bytes_recv']).'</td>';
            $html .= '      <td>'.htmlspecialchars($s['bytes_sent']).'</td>';
            $html .= '      <td>'.htmlspecialchars($s['connected_since']).'</td>';
            $html .= '    </tr>';
        }
    }
    $html .= '  </table>';

    $html .= '  <div class="easyvpn-message">';
    $html .= '    '._tr("Los perfiles generan archivos en").' <code>/etc/openvpn/easyvpn/generated</code>';
    $html .= '  </div>';

    $html .= '</div>';

    // Auto-refresh de la tabla de clientes conectados
    $html .= "\n<script>\n";
    $html .= "document.addEventListener('DOMContentLoaded', function() {\n";
    $html .= "    function refreshEasyVPNStatus() {\n";
    $html .= "        var table = document.getElementById('easyvpn-status-table');\n";
    $html .= "        var indicator = document.getElementById('easyvpn-status-indicator');\n";
    $html .= "        if (!table) return;\n";
    $html .= "\n";
    $html .= "        if (indicator) {\n";
    $html .= "            indicator.textContent = 'Actualizando...';\n";
    $html .= "            indicator.classList.add('easyvpn-blink');\n";
    $html .= "        }\n";
    $html .= "\n";
    $html .= "        fetch(window.location.href)\n";
    $html .= "            .then(function(r) { return r.text(); })\n";
    $html .= "            .then(function(html) {\n";
    $html .= "                var parser = new DOMParser();\n";
    $html .= "                var doc = parser.parseFromString(html, 'text/html');\n";
    $html .= "                var newTable = doc.querySelector('#easyvpn-status-table');\n";
    $html .= "                if (newTable) {\n";
    $html .= "                    table.innerHTML = newTable.innerHTML;\n";
    $html .= "                }\n";
    $html .= "                if (indicator) {\n";
    $html .= "                    indicator.textContent = 'Actualizado';\n";
    $html .= "                    indicator.classList.remove('easyvpn-blink');\n";
    $html .= "                }\n";
    $html .= "            })\n";
    $html .= "            .catch(function() {\n";
    $html .= "                if (indicator) {\n";
    $html .= "                    indicator.textContent = 'Error al actualizar';\n";
    $html .= "                    indicator.classList.remove('easyvpn-blink');\n";
    $html .= "                }\n";
    $html .= "            });\n";
    $html .= "    }\n";
    $html .= "\n";
    $html .= "    setTimeout(refreshEasyVPNStatus, 2000);\n";
    $html .= "    setInterval(refreshEasyVPNStatus, 5000);\n";
    $html .= "});\n";
    $html .= "</script>\n";

    return $html;
}
