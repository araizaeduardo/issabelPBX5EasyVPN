<?php
// Funciones helper para el módulo EasyVPN

// Lee /etc/openvpn/easyvpn/pki/index.txt y regresa lista de clientes
function easyvpn_list_clients() {
    $easyrsaIndex = "/etc/openvpn/easyvpn/pki/index.txt";
    $clients = array();

    if (!file_exists($easyrsaIndex) || !is_readable($easyrsaIndex)) {
        return $clients;
    }

    $lines = file($easyrsaIndex, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        // Ejemplo de línea:
        // V  280310191729Z   <vacío>    SERIAL    unknown    /CN=prueba1
        $parts = explode("\t", $line);
        if (count($parts) < 2) continue;

        $status = $parts[0];         // V, R, etc.
        $dn     = trim(end($parts)); // Tomamos SIEMPRE la ÚLTIMA columna (/CN=...)

        // Extraer CN desde algo como "/CN=prueba1"
        $cn = $dn;
        if (strpos($dn, "/CN=") !== false) {
            $cn = substr($dn, strpos($dn, "/CN=") + 4);
        } elseif (strpos($dn, "CN=") !== false) {
            $cn = substr($dn, strpos($dn, "CN=") + 3);
        }

        $cn = trim($cn);
        if ($cn === '' || $cn === 'server') {
            // Saltar la entrada del servidor
            continue;
        }

        $clients[] = array(
            'cn'     => $cn,
            'status' => $status,
        );
    }

    return $clients;
}

// Crea un cliente llamando al script shell
function easyvpn_create_client($name, &$error) {
    $error = '';

    // Normalizar nombre
    $name = preg_replace('/[^a-zA-Z0-9_\-]/', '_', $name);
    if (strlen($name) < 3) {
        $error = "Nombre demasiado corto (mínimo 3 caracteres).";
        return false;
    }

    // Ejecutar como root vía sudo (configurado en /etc/sudoers.d/easyvpn)
    $cmd = 'sudo /usr/local/sbin/easyvpn-create-client.sh ' . escapeshellarg($name) . ' 2>&1';
    exec($cmd, $output, $ret);

    if ($ret !== 0) {
        $error = "Error creando cliente:\n".implode("\n", $output);
        return false;
    }

    return true;
}

// Revoca un cliente (CN) llamando al script de shell
function easyvpn_revoke_client($cn, &$error) {
    $error = '';

    // Normalizar igual que en la creación
    $cnSafe = preg_replace('/[^a-zA-Z0-9_\-]/', '_', $cn);
    if ($cnSafe === '' || $cnSafe === 'server') {
        $error = "CN inválido para revocar.";
        return false;
    }

    $cmd = 'sudo /usr/local/sbin/easyvpn-revoke-client.sh ' . escapeshellarg($cnSafe) . ' 2>&1';
    exec($cmd, $output, $ret);

    if ($ret !== 0) {
        $error = "Error revocando cliente '$cnSafe':\n".implode("\n", $output);
        return false;
    }

    return true;
}


// Lee status de OpenVPN
function easyvpn_get_status() {
    $statusFile = "/var/log/openvpn/easyvpn-status.log";
    $clients = array();

    if (!file_exists($statusFile) || !is_readable($statusFile)) {
        return $clients;
    }

    $lines = file($statusFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        // Formato status-version 2:
        // CLIENT_LIST,CN,Real Address,Virtual Address,Virtual IPv6,BytesRecv,BytesSent,Connected Since,Connected Since (time_t),Username,ClientID,PeerID
        if (strpos($line, 'CLIENT_LIST,') === 0) {
            $parts = str_getcsv($line);
            if (count($parts) < 11) {
                continue;
            }

            $clients[] = array(
                'cn'              => $parts[1],
                'real_address'    => $parts[2],
                'virtual_address' => $parts[3],
                'bytes_recv'      => $parts[5],
                'bytes_sent'      => $parts[6],
                'connected_since' => $parts[7],
                'client_id'       => $parts[10],
            );
        }
    }

    return $clients;
}

// Obtiene rutas de archivos .ovpn y .tar para un CN dado
function easyvpn_get_client_files($cn) {
    $baseDir = "/etc/openvpn/easyvpn/generated";

    // Normalizar igual que al crear
    $cnSafe = preg_replace('/[^a-zA-Z0-9_\-]/', '_', $cn);

    $ovpn = $baseDir . "/" . $cnSafe . ".ovpn";
    $tar  = $baseDir . "/" . $cnSafe . "-grandstream.tar";

    $files = array(
        'ovpn' => file_exists($ovpn) ? $ovpn : null,
        'tar'  => file_exists($tar)  ? $tar  : null,
    );

    return $files;
}


function easyvpn_regenerate_profile($cn, &$error) {
    $error = '';
    $cn = trim($cn);

    if (!preg_match('/^[A-Za-z0-9_.\-]+$/', $cn)) {
        $error = "CN inválido.";
        return false;
    }

    $cmd = "sudo /usr/local/sbin/easyvpn-regenerate-profile.sh " . escapeshellarg($cn) . " 2>&1";
    exec($cmd, $output, $ret);

    if ($ret !== 0) {
        $error = "Error regenerando perfil para '$cn':\n".implode("\n", $output);
        return false;
    }

    return true;
}


function easyvpn_disconnect_client($clientId, &$error) {
    $error = '';
    $clientId = trim($clientId);

    if ($clientId === '' || !ctype_digit($clientId)) {
        $error = "Client ID inválido.";
        return false;
    }

    $cmd = 'sudo /usr/local/sbin/easyvpn-kick-client.sh ' . escapeshellarg($clientId) . ' 2>&1';
    exec($cmd, $output, $ret);

    if ($ret !== 0) {
        $error = "Error al desconectar cliente (ID $clientId):\n".implode("\n", $output);
        return false;
    }

    return true;
}


function easyvpn_get_service_status() {
    $cmd = 'sudo /usr/local/sbin/easyvpn-service.sh status 2>&1';
    exec($cmd, $output, $ret);
    $status = trim(implode("\n", $output));

    if ($status === 'active') {
        return 'active';
    } elseif ($status === 'inactive') {
        return 'inactive';
    } elseif ($status === 'failed') {
        return 'failed';
    } else {
        return 'unknown';
    }
}


function easyvpn_control_service($op, &$error) {
    $error = '';
    $op = trim($op);

    if (!in_array($op, array('start', 'stop', 'restart'), true)) {
        $error = "Operación inválida.";
        return false;
    }

    $cmd = 'sudo /usr/local/sbin/easyvpn-service.sh ' . escapeshellarg($op) . ' 2>&1';
    exec($cmd, $output, $ret);

    if ($ret !== 0) {
        $error = "Error al ejecutar '$op' en el servicio:\n".implode("\n", $output);
        return false;
    }

    return true;
}


