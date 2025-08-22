# backend/app/services/notify/providers/colombiared_provider.py
class ColombiaRedProvider:
    def __init__(self, base_url: str, user: str, password: str, sender: str | None = None) -> None:
        self.base_url = base_url
        self.user = user
        self.password = password
        self.sender = sender

    def send_sms(self, to: str, body: str) -> None:
        # Aquí implementarás la llamada HTTP real cuando tengas el proveedor listo
        print(f"[ColombiaRED] Enviando a {to} desde {self.sender or '(sin sender)'}: {body}")
