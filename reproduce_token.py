
import hashlib
import time
import base64

filename = "caramelo"
secret = "LUANDI_SECRET_KEY_QM9"
# Use a slightly future timestamp to ensure it's valid by the time curl runs
timestamp = str(int(time.time_ns()) + 1000000000) 

hash_input = (filename + timestamp + secret).encode('utf-8')
signature = hashlib.sha256(hash_input).digest()
signature_safe = base64.urlsafe_b64encode(signature).decode('utf-8').rstrip('=')

token = f"{timestamp}.{signature_safe}"
print(f"Token: {token}")
