# views.py
from django.shortcuts import redirect
from django.http import HttpResponse

def redirect_view(request):
    response = redirect('admin/')
    return response

def access_denied(request):
    return HttpResponse('Usuario no autorizado',status=401)