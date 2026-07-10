from rest_framework.negotiation import BaseContentNegotiation


class JsonOnlyContentNegotiation(BaseContentNegotiation):
    def select_renderer(self, request, renderers, format_suffix=None):
        return renderers[0], renderers[0].media_type

    def select_parser(self, request, parsers):
        return parsers[0] if parsers else None
