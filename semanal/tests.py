from django.test import TestCase
from .models import Informe, Contenido

class ContenidoModelTests(TestCase):
    # NO FUNCIONA!
    def test_fecha_contenido_equals_fecha_when_blank(self):
        informe = Informe(fecha="2000-01-01",texto_general="test")
        contenido = Contenido(fecha=informe.fecha,texto="test")
        contenido.save()
        self.assertIs(contenido.fecha_actualizado,contenido.fecha)
