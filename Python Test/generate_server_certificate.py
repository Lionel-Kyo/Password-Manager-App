import datetime
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

def generate_ecdsa_certificate():
    private_key = ec.generate_private_key(ec.SECP256R1())

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "WebSocket Crypto Server"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "WebSocket Server"),
    ])

    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=1825))
        .sign(private_key, hashes.SHA256())
    )

    cert_pem = cert.public_bytes(serialization.Encoding.PEM)
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )

    with open("server_cert.pem", "wb") as f:
        f.write(cert_pem)
    with open("server_key.pem", "wb") as f:
        f.write(key_pem)

    print("Certificate and key successfully generated!")
    print("\n--- Environment Variables Format ---")
    print(f"SERVER_CERT_PEM=`{cert_pem.decode('utf-8').strip()}`")
    print(f"SERVER_KEY_PEM=`{key_pem.decode('utf-8').strip()}`")

if __name__ == "__main__":
    generate_ecdsa_certificate()