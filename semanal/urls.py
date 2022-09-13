from django.urls import path

from . import views

app_name = 'semanal'
urlpatterns = [
    path('', views.IndexView.as_view(), name='index'),
    # path('', views.index, name='index'),
    #path('informe', views.IndexView.as_view(), name='index'),
    # path('informe', views.index, name='index'),
    #path('informe/<str:pk>', views.InformeView.as_view(), name='informe'),
    # path('informe/<str:fecha>', views.informe, name='informe'),
    #path('informe/<str:fecha>/<str:region_id>', views.contenido, name='contenido'),
    ## API
    path('api/regiones', views.api_regiones, name="api_regiones"),
    path('api/regiones/<str:pk>', views.api_region, name="api_region"),
    path('api/tramos', views.api_tramos, name="api_tramos"),
    path('api/tramos/<str:pk>', views.api_tramo, name="api_tramo"),
    path('api/secciones', views.api_secciones, name="api_secciones"),
    path('api/secciones/<str:pk>', views.api_seccion, name="api_seccion"),
    path('api/informes/<str:pk>', views.api_informe, name="api_informe"),
    path('api/informes/', views.api_informe, name="api_informe"),
    path('api/informes', views.api_informe, name="api_informe"),
    path('api/informe', views.api_informe, name="api_informe"),
    path('import/informe', views.ImportInformeView.as_view(), name="import_informe"),
    path('import/informe/handson_view', views.embed_informe_handson_table, name="informe_handson_view"),
    path('import/informe/handson_view/<str:pk>', views.informe_handson_table_view, name="informe_handson_table_view"),
    path('import', views.imports, name="imports"),
    # path('import/informe/handson_view/<str:pk>', views.embed_informe_handson_table_fecha, name="informe_handson_view_fecha"),
]